package shared

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

const (
	MntPoint = "/mnt/repo"
)

var (
	BucketName = "venom-testing"
	IndexFiles = [1]string{
		"stone.index",
	}
	RepoDir = ""
)

func isStone(path string) bool {
	return filepath.Ext(path) == ".stone"
}

func DeleteFile(path string) error {
	if _, err := os.Stat(path); err == nil {
		err := os.Remove(path)
		if err != nil {
			return errors.New(fmt.Sprint("Failed to delete package at", path, ":", err))
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New(fmt.Sprint("Unable to check if file", path, "exists:", err))
	}

	return nil
}
