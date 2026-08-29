package procore

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

var ErrBoundary = errors.New("invalid Procore adapter response")

type TokenSource interface {
	Token(context.Context) (string, error)
}

type Config struct {
	BaseURL    string
	CompanyID  int64
	Token      TokenSource
	HTTPClient *http.Client
	PerPage    int
}

type Project struct {
	ExternalID    string
	Name          string
	ProjectNumber string
	SourceSystem  string
	SourceVersion string
}

type Client struct {
	baseURL    *url.URL
	companyID  int64
	token      TokenSource
	httpClient *http.Client
	perPage    int
}

func New(config Config) (*Client, error) {
	if config.CompanyID <= 0 || config.Token == nil {
		return nil, errors.New("company ID and token source are required")
	}
	baseURL, err := url.Parse(config.BaseURL)
	if err != nil || baseURL.Scheme == "" || baseURL.Host == "" ||
		(baseURL.Scheme != "https" && baseURL.Scheme != "http") {
		return nil, errors.New("base URL must be an HTTP(S) URL")
	}
	perPage := config.PerPage
	if perPage == 0 {
		perPage = 100
	}
	if perPage < 1 || perPage > 100 {
		return nil, errors.New("per-page must be between 1 and 100")
	}
	httpClient := config.HTTPClient
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &Client{
		baseURL:    baseURL,
		companyID:  config.CompanyID,
		token:      config.Token,
		httpClient: httpClient,
		perPage:    perPage,
	}, nil
}

func (c *Client) ListProjects(ctx context.Context) ([]Project, error) {
	projects := make([]Project, 0)
	for page := 1; page <= 1000; page++ {
		token, err := c.token.Token(ctx)
		if err != nil {
			return nil, fmt.Errorf("Procore token source: %w", err)
		}
		if strings.TrimSpace(token) == "" {
			return nil, ErrBoundary
		}
		endpoint := *c.baseURL
		endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/rest/v1.0/companies/" + strconv.FormatInt(c.companyID, 10) + "/projects"
		query := endpoint.Query()
		query.Set("page", strconv.Itoa(page))
		query.Set("per_page", strconv.Itoa(c.perPage))
		endpoint.RawQuery = query.Encode()
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
		if err != nil {
			return nil, fmt.Errorf("build Procore request: %w", err)
		}
		request.Header.Set("Authorization", "Bearer "+token)
		request.Header.Set("Procore-Company-Id", strconv.FormatInt(c.companyID, 10))
		request.Header.Set("Accept", "application/json")
		response, err := c.httpClient.Do(request)
		if err != nil {
			return nil, fmt.Errorf("Procore request: %w", err)
		}
		body, readErr := io.ReadAll(io.LimitReader(response.Body, 4<<20))
		closeErr := response.Body.Close()
		if readErr != nil || closeErr != nil {
			return nil, ErrBoundary
		}
		if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
			return nil, ErrBoundary
		}
		var raw []struct {
			ID            json.RawMessage `json:"id"`
			Name          string          `json:"name"`
			ProjectNumber string          `json:"project_number"`
		}
		if json.Unmarshal(body, &raw) != nil {
			return nil, ErrBoundary
		}
		for _, item := range raw {
			id, err := canonicalID(item.ID)
			if err != nil || strings.TrimSpace(item.Name) == "" {
				return nil, ErrBoundary
			}
			projects = append(projects, Project{
				ExternalID:    id,
				Name:          item.Name,
				ProjectNumber: item.ProjectNumber,
				SourceSystem:  "procore",
				SourceVersion: "rest.v1.0",
			})
		}
		if !hasNextPage(response.Header.Get("Link")) && len(raw) < c.perPage {
			return projects, nil
		}
		if link := response.Header.Get("Link"); link != "" {
			if !hasNextPage(link) {
				return projects, nil
			}
		}
	}
	return nil, ErrBoundary
}

func canonicalID(raw json.RawMessage) (string, error) {
	var number int64
	if json.Unmarshal(raw, &number) == nil && number > 0 {
		return strconv.FormatInt(number, 10), nil
	}
	var text string
	if json.Unmarshal(raw, &text) == nil && strings.TrimSpace(text) != "" {
		if _, err := strconv.ParseInt(text, 10, 64); err != nil {
			return "", err
		}
		return text, nil
	}
	return "", ErrBoundary
}

func hasNextPage(link string) bool {
	for _, part := range strings.Split(link, ",") {
		if strings.Contains(strings.ToLower(part), `rel="next"`) {
			return true
		}
	}
	return false
}
