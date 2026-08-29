package core

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"regexp"
)

var (
	ErrBoundary = errors.New("invalid recovery core boundary response")
	hashPattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

type Response struct {
	Status string          `json:"status"`
	Record json.RawMessage `json:"record,omitempty"`
	Code   string          `json:"code,omitempty"`
}

type ProcessRunner struct {
	binary string
}

func NewProcessRunner(binary string) (*ProcessRunner, error) {
	if binary == "" {
		return nil, errors.New("recovery core binary is required")
	}
	return &ProcessRunner{binary: binary}, nil
}

func (r *ProcessRunner) Evaluate(ctx context.Context, request []byte) (Response, error) {
	command := exec.CommandContext(ctx, r.binary)
	command.Stdin = bytes.NewReader(request)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		return Response{}, fmt.Errorf("recovery core process: %w", err)
	}
	return ParseResponse(stdout.Bytes())
}

func ParseResponse(raw []byte) (Response, error) {
	var response Response
	if err := json.Unmarshal(raw, &response); err != nil {
		return Response{}, ErrBoundary
	}
	switch response.Status {
	case "ERROR":
		if response.Code == "" || len(response.Record) != 0 {
			return Response{}, ErrBoundary
		}
	case "SUCCESS":
		if response.Code != "" || len(response.Record) == 0 {
			return Response{}, ErrBoundary
		}
		var record struct {
			EvaluationHash string `json:"evaluation_hash"`
		}
		if json.Unmarshal(response.Record, &record) != nil || !hashPattern.MatchString(record.EvaluationHash) {
			return Response{}, ErrBoundary
		}
	default:
		return Response{}, ErrBoundary
	}
	return response, nil
}
