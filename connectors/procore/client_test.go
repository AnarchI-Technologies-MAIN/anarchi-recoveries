package procore

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type staticToken string

func (token staticToken) Token(context.Context) (string, error) { return string(token), nil }

func TestListProjectsMapsReadOnlyPaginatedResponses(t *testing.T) {
	var requests int
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		requests++
		if request.Method != http.MethodGet || request.Header.Get("Authorization") != "Bearer test-token" ||
			request.Header.Get("Procore-Company-Id") != "42" {
			t.Fatalf("unexpected request: %#v", request)
		}
		if request.URL.Query().Get("per_page") != "2" {
			t.Fatalf("expected explicit per_page, got %s", request.URL.RawQuery)
		}
		if request.URL.Query().Get("page") == "1" {
			writer.Header().Set("Link", `<http://`+request.Host+`/rest/v1.0/companies/42/projects?page=2&per_page=2>; rel="next"`)
			_, _ = writer.Write([]byte(`[{"id":101,"name":"Alpha","project_number":"A-1"},{"id":"102","name":"Beta"}]`))
			return
		}
		_, _ = writer.Write([]byte(`[{"id":103,"name":"Gamma","project_number":"G-3"}]`))
	}))
	defer server.Close()

	client, err := New(Config{BaseURL: server.URL, CompanyID: 42, Token: staticToken("test-token"), PerPage: 2})
	if err != nil {
		t.Fatal(err)
	}
	projects, err := client.ListProjects(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if requests != 2 || len(projects) != 3 || projects[1].ExternalID != "102" || projects[2].ProjectNumber != "G-3" {
		t.Fatalf("unexpected canonical projects: %#v requests=%d", projects, requests)
	}
}

func TestListProjectsFailsClosedWithoutLeakingResponseBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.WriteHeader(http.StatusUnauthorized)
		_, _ = writer.Write([]byte(`secret-token-must-not-escape`))
	}))
	defer server.Close()
	client, err := New(Config{BaseURL: server.URL, CompanyID: 42, Token: staticToken("secret-token")})
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.ListProjects(context.Background())
	if !errors.Is(err, ErrBoundary) || strings.Contains(err.Error(), "secret-token") {
		t.Fatalf("expected redacted boundary error, got %v", err)
	}
}

func TestListProjectsRejectsMalformedCanonicalProject(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		_, _ = writer.Write([]byte(`[{"id":0,"name":"forged"}]`))
	}))
	defer server.Close()
	client, err := New(Config{BaseURL: server.URL, CompanyID: 42, Token: staticToken("test-token")})
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.ListProjects(context.Background())
	if !errors.Is(err, ErrBoundary) {
		t.Fatalf("expected boundary rejection, got %v", err)
	}
}
