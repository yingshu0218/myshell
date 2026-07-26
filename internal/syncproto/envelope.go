package syncproto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"regexp"
)

const (
	MaxPlaintext = 1 << 20
	nonceSize    = 12
	headerSize   = 3
)

var (
	header     = [headerSize]byte{'M', 'S', 1}
	validID    = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)
	ErrInvalid = errors.New("invalid sync envelope")
	ErrAuth    = errors.New("sync envelope authentication failed")
)

type Context struct {
	AppID         string
	Collection    string
	RecordID      string
	SchemaVersion int
}

func Seal(key, plaintext []byte, context Context) ([]byte, string, error) {
	nonce := make([]byte, nonceSize)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, "", err
	}
	return SealWithNonce(key, nonce, plaintext, context)
}

func SealWithNonce(key, nonce, plaintext []byte, context Context) ([]byte, string, error) {
	if err := validate(key, nonce, plaintext, context); err != nil {
		return nil, "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, "", ErrInvalid
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, "", ErrInvalid
	}
	payload := make([]byte, 0, headerSize+nonceSize+len(plaintext)+gcm.Overhead())
	payload = append(payload, header[:]...)
	payload = append(payload, nonce...)
	payload = gcm.Seal(payload, nonce, plaintext, additionalData(context))
	sum := sha256.Sum256(payload)
	return payload, base64.RawURLEncoding.EncodeToString(sum[:]), nil
}

func Open(key, payload []byte, checksum string, context Context) ([]byte, error) {
	if len(key) != 32 || len(payload) < headerSize+nonceSize+16 ||
		payload[0] != header[0] || payload[1] != header[1] || payload[2] != header[2] ||
		!validContext(context) {
		return nil, ErrInvalid
	}
	sum := sha256.Sum256(payload)
	if checksum != base64.RawURLEncoding.EncodeToString(sum[:]) {
		return nil, ErrInvalid
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, ErrInvalid
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, ErrInvalid
	}
	nonce := payload[headerSize : headerSize+nonceSize]
	plaintext, err := gcm.Open(nil, nonce, payload[headerSize+nonceSize:], additionalData(context))
	if err != nil {
		return nil, ErrAuth
	}
	if len(plaintext) > MaxPlaintext {
		return nil, ErrInvalid
	}
	return plaintext, nil
}

func validate(key, nonce, plaintext []byte, context Context) error {
	if len(key) != 32 || len(nonce) != nonceSize || len(plaintext) > MaxPlaintext || !validContext(context) {
		return ErrInvalid
	}
	return nil
}

func validContext(context Context) bool {
	return validID.MatchString(context.AppID) &&
		validID.MatchString(context.Collection) &&
		validID.MatchString(context.RecordID) &&
		context.SchemaVersion > 0
}

func additionalData(context Context) []byte {
	return []byte(fmt.Sprintf("myshell-sync|v1|%s|%s|%s|%d",
		context.AppID, context.Collection, context.RecordID, context.SchemaVersion))
}
