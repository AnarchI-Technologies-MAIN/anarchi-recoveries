package quickbooks

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type staticToken string

func (token staticToken) Token(context.Context) (string, error) { return string(token), nil }

func TestListInvoicesUsesExplicitQueryPagination(t *testing.T) {
	var requests int
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		requests++
		if request.Method != http.MethodPost || request.URL.Path != "/v3/company/123/query" ||
			request.URL.Query().Get("minorversion") != "75" || request.Header.Get("Authorization") != "Bearer test-token" ||
			request.Header.Get("Content-Type") != "application/text" {
			t.Fatalf("unexpected request: %#v", request)
		}
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Fatal(err)
		}
		if requests == 1 {
			if string(body) != "select * from Invoice startposition 1 maxresults 2" {
				t.Fatalf("unexpected first query: %s", body)
			}
			_, _ = writer.Write([]byte(`{"QueryResponse":{"Invoice":[{"Id":"10","TxnDate":"2026-08-01","TotalAmt":"100.25","CurrencyRef":{"value":"USD"}},{"Id":"11","TxnDate":"2026-08-02","TotalAmt":25.75,"CurrencyRef":{"value":"USD"}}]}}`))
			return
		}
		if string(body) != "select * from Invoice startposition 3 maxresults 2" {
			t.Fatalf("unexpected second query: %s", body)
		}
		_, _ = writer.Write([]byte(`{"QueryResponse":{"Invoice":[{"Id":"12","TxnDate":"2026-08-03","TotalAmt":"50.00","CurrencyRef":{"value":"USD"},"CustomerRef":{"value":"C-1"}}]}}`))
	}))
	defer server.Close()
	client, err := New(Config{BaseURL: server.URL, RealmID: "123", MinorVersion: "75", Token: staticToken("test-token"), PageSize: 2})
	if err != nil {
		t.Fatal(err)
	}
	observations, err := client.List(context.Background(), EntityInvoice)
	if err != nil || requests != 2 || len(observations) != 3 || observations[1].TotalAmount != "25.75" || observations[2].CustomerExternalID != "C-1" {
		t.Fatalf("unexpected observations=%#v requests=%d err=%v", observations, requests, err)
	}
}

func TestListPaymentsPreservesLinkedInvoices(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		_, _ = writer.Write([]byte(`{"QueryResponse":{"Payment":[{"Id":"20","TxnDate":"2026-08-04","TotalAmt":"40.00","CurrencyRef":{"value":"USD"},"Line":[{"LinkedTxn":[{"TxnId":"10","TxnType":"Invoice"},{"TxnId":"x","TxnType":"Bill"}]}]}]}}`))
	}))
	defer server.Close()
	client, err := New(Config{BaseURL: server.URL, RealmID: "123", MinorVersion: "75", Token: staticToken("test-token")})
	if err != nil {
		t.Fatal(err)
	}
	observations, err := client.List(context.Background(), EntityPayment)
	if err != nil || len(observations) != 1 || len(observations[0].LinkedInvoiceIDs) != 1 || observations[0].LinkedInvoiceIDs[0] != "10" {
		t.Fatalf("unexpected payment observations=%#v err=%v", observations, err)
	}
}

func TestListFailsClosedAndRedactsResponseBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusUnauthorized)
		_, _ = writer.Write([]byte(`secret-token-must-not-escape`))
	}))
	defer server.Close()
	client, err := New(Config{BaseURL: server.URL, RealmID: "123", MinorVersion: "75", Token: staticToken("secret-token")})
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.List(context.Background(), EntityInvoice)
	if !errors.Is(err, ErrBoundary) || strings.Contains(err.Error(), "secret-token") {
		t.Fatalf("expected redacted boundary error, got %v", err)
	}
}

func TestListRejectsUnsupportedEntityAndInvalidAmount(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		_, _ = writer.Write([]byte(`{"QueryResponse":{"Invoice":[{"Id":"10","TxnDate":"2026-08-01","TotalAmt":"not-money","CurrencyRef":{"value":"USD"}}]}}`))
	}))
	defer server.Close()
	client, err := New(Config{BaseURL: server.URL, RealmID: "123", MinorVersion: "75", Token: staticToken("test-token")})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.List(context.Background(), Entity("Customer")); !errors.Is(err, ErrBoundary) {
		t.Fatalf("expected unsupported entity rejection, got %v", err)
	}
	if _, err := client.List(context.Background(), EntityInvoice); !errors.Is(err, ErrBoundary) {
		t.Fatalf("expected invalid amount rejection, got %v", err)
	}
}
