package evidence

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	uuidPattern   = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
	sha256Pattern = regexp.MustCompile(`^[0-9a-f]{64}$`)
	ErrIdentity   = errors.New("invalid evidence identity")
	ErrHash       = errors.New("evidence sha256 mismatch")
	ErrSize       = errors.New("evidence size mismatch")
)

type Identity struct {
	OrganizationID string
	ProjectID      string
	EvidenceID     string
	SHA256         string
	Filename       string
}

func ObjectKey(v Identity) (string, error) {
	if !uuidPattern.MatchString(v.OrganizationID) || !uuidPattern.MatchString(v.ProjectID) || !uuidPattern.MatchString(v.EvidenceID) {
		return "", ErrIdentity
	}
	if !sha256Pattern.MatchString(v.SHA256) {
		return "", ErrIdentity
	}
	if v.Filename == "" || strings.TrimSpace(v.Filename) != v.Filename || filepath.Base(v.Filename) != v.Filename || v.Filename == "." || v.Filename == ".." || strings.Contains(v.Filename, `\`) {
		return "", ErrIdentity
	}
	return fmt.Sprintf("org/%s/project/%s/evidence/%s/%s/%s", v.OrganizationID, v.ProjectID, v.EvidenceID, v.SHA256, v.Filename), nil
}

func Verify(r io.Reader, expectedSHA256 string, expectedSize int64) error {
	if !sha256Pattern.MatchString(expectedSHA256) || expectedSize < 0 {
		return ErrIdentity
	}
	h := sha256.New()
	n, err := io.Copy(h, r)
	if err != nil {
		return fmt.Errorf("read evidence: %w", err)
	}
	if n != expectedSize {
		return ErrSize
	}
	if hex.EncodeToString(h.Sum(nil)) != expectedSHA256 {
		return ErrHash
	}
	return nil
}
