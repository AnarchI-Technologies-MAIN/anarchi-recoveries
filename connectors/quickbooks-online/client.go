package quickbooks

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

var (
	ErrBoundary   = errors.New("invalid QuickBooks Online adapter response")
	amountPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)(\.[0-9]+)?$`)
)

type TokenSource interface {
	Token(context.Context) (string, error)
}

type Entity string

const (
	EntityInvoice Entity = "Invoice"
	EntityPayment Entity = "Payment"
)

type Config struct {
	BaseURL      string
	RealmID      string
	MinorVersion string
	Token        TokenSource
	HTTPClient   *http.Client
	PageSize     int
}

type Observation struct {
	EntityType         Entity
	ExternalID         string
	TransactionDate    string
	TotalAmount        string
	Currency           string
	CustomerExternalID string
	LinkedInvoiceIDs   []string
	SourceSystem       string
	SourceVersion      string
}

type Client struct {
	baseURL      *url.URL
	realmID      string
	minorVersion string
	token        TokenSource
	httpClient   *http.Client
	pageSize     int
}

func New(config Config) (*Client, error) {
	if strings.TrimSpace(config.RealmID) == "" || strings.TrimSpace(config.MinorVersion) == "" || config.Token == nil {
		return nil, errors.New("realm ID, minor version, and token source are required")
	}
	if _, err := strconv.ParseUint(config.RealmID, 10, 64); err != nil {
		return nil, errors.New("realm ID must be numeric")
	}
	baseURL, err := url.Parse(config.BaseURL)
	if err != nil || baseURL.Scheme == "" || baseURL.Host == "" ||
		(baseURL.Scheme != "https" && baseURL.Scheme != "http") {
		return nil, errors.New("base URL must be an HTTP(S) URL")
	}
	pageSize := config.PageSize
	if pageSize == 0 {
		pageSize = 100
	}
	if pageSize < 1 || pageSize > 1000 {
		return nil, errors.New("page size must be between 1 and 1000")
	}
	httpClient := config.HTTPClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Client{
		baseURL:      baseURL,
		realmID:      config.RealmID,
		minorVersion: config.MinorVersion,
		token:        config.Token,
		httpClient:   httpClient,
		pageSize:     pageSize,
	}, nil
}

func (c *Client) List(ctx context.Context, entity Entity) ([]Observation, error) {
	if entity != EntityInvoice && entity != EntityPayment {
		return nil, ErrBoundary
	}
	observations := make([]Observation, 0)
	for page, start := 0, 1; page < 1000; page, start = page+1, start+c.pageSize {
		token, err := c.token.Token(ctx)
		if err != nil {
			return nil, fmt.Errorf("QuickBooks token source: %w", err)
		}
		if strings.TrimSpace(token) == "" {
			return nil, ErrBoundary
		}
		endpoint := *c.baseURL
		endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/v3/company/" + c.realmID + "/query"
		query := endpoint.Query()
		query.Set("minorversion", c.minorVersion)
		endpoint.RawQuery = query.Encode()
		statement := "select * from " + string(entity) + " startposition " + strconv.Itoa(start) + " maxresults " + strconv.Itoa(c.pageSize)
		request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint.String(), strings.NewReader(statement))
		if err != nil {
			return nil, fmt.Errorf("build QuickBooks request: %w", err)
		}
		request.Header.Set("Authorization", "Bearer "+token)
		request.Header.Set("Accept", "application/json")
		request.Header.Set("Content-Type", "application/text")
		response, err := c.httpClient.Do(request)
		if err != nil {
			return nil, fmt.Errorf("QuickBooks request: %w", err)
		}
		body, readErr := io.ReadAll(io.LimitReader(response.Body, 8<<20))
		closeErr := response.Body.Close()
		if readErr != nil || closeErr != nil {
			return nil, ErrBoundary
		}
		if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
			return nil, ErrBoundary
		}
		var envelope struct {
			QueryResponse map[string]json.RawMessage `json:"QueryResponse"`
		}
		if json.Unmarshal(body, &envelope) != nil || envelope.QueryResponse == nil {
			return nil, ErrBoundary
		}
		var rows []map[string]json.RawMessage
		if raw := envelope.QueryResponse[string(entity)]; len(raw) > 0 {
			if json.Unmarshal(raw, &rows) != nil {
				return nil, ErrBoundary
			}
		}
		for _, row := range rows {
			observation, err := normalize(entity, row)
			if err != nil {
				return nil, err
			}
			observations = append(observations, observation)
		}
		if len(rows) < c.pageSize {
			return observations, nil
		}
	}
	return nil, ErrBoundary
}

func normalize(entity Entity, row map[string]json.RawMessage) (Observation, error) {
	id, err := requiredString(row, "Id")
	if err != nil {
		return Observation{}, ErrBoundary
	}
	transactionDate, err := requiredString(row, "TxnDate")
	if err != nil {
		return Observation{}, ErrBoundary
	}
	totalAmount, err := requiredScalar(row, "TotalAmt")
	if err != nil || !amountPattern.MatchString(totalAmount) || totalAmount == "0" || strings.HasPrefix(totalAmount, "0.") && strings.Trim(totalAmount[2:], "0") == "" {
		return Observation{}, ErrBoundary
	}
	currency, err := nestedString(row, "CurrencyRef", "value")
	if err != nil || len(currency) != 3 || currency != strings.ToUpper(currency) {
		return Observation{}, ErrBoundary
	}
	customerID, _ := nestedString(row, "CustomerRef", "value")
	observation := Observation{
		EntityType:         entity,
		ExternalID:         id,
		TransactionDate:    transactionDate,
		TotalAmount:        totalAmount,
		Currency:           currency,
		CustomerExternalID: customerID,
		SourceSystem:       "quickbooks-online",
		SourceVersion:      "accounting-api-v3",
	}
	if entity == EntityPayment {
		observation.LinkedInvoiceIDs = linkedInvoiceIDs(row)
	}
	return observation, nil
}

func requiredString(row map[string]json.RawMessage, key string) (string, error) {
	var value string
	if json.Unmarshal(row[key], &value) != nil || strings.TrimSpace(value) == "" {
		return "", ErrBoundary
	}
	return value, nil
}

func requiredScalar(row map[string]json.RawMessage, key string) (string, error) {
	raw := row[key]
	if len(raw) == 0 {
		return "", ErrBoundary
	}
	var value string
	if json.Unmarshal(raw, &value) == nil {
		return value, nil
	}
	var number json.Number
	if json.Unmarshal(raw, &number) == nil {
		return number.String(), nil
	}
	return "", ErrBoundary
}

func nestedString(row map[string]json.RawMessage, objectKey, valueKey string) (string, error) {
	var object map[string]json.RawMessage
	if json.Unmarshal(row[objectKey], &object) != nil {
		return "", ErrBoundary
	}
	return requiredString(object, valueKey)
}

func linkedInvoiceIDs(row map[string]json.RawMessage) []string {
	var lines []struct {
		LinkedTxn []struct {
			TxnID   string `json:"TxnId"`
			TxnType string `json:"TxnType"`
		} `json:"LinkedTxn"`
	}
	if json.Unmarshal(row["Line"], &lines) != nil {
		return nil
	}
	ids := make([]string, 0)
	for _, line := range lines {
		for _, linked := range line.LinkedTxn {
			if linked.TxnType == "Invoice" && strings.TrimSpace(linked.TxnID) != "" {
				ids = append(ids, linked.TxnID)
			}
		}
	}
	return ids
}
