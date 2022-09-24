package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/GZGavinZhao/venom-repo/fc/shared"
	"github.com/aliyun/aliyun-oss-go-sdk/oss"
	"github.com/aliyun/fc-runtime-go-sdk/events"
	gr "github.com/awesome-fc/golang-runtime"
)

func HandleRequest(ctx *gr.FCContext, rawEvents []byte) ([]byte, error) {
	credentials := ctx.Credentials
	logger := ctx.GetLogger()
	var event events.OssEvent
	err := json.Unmarshal(rawEvents, &event)
	if err != nil {
		logger.Errorln("Unable to marshall json to OssEvent, err:", err)
	}

	bucketFromEnv := os.Getenv("BUCKET")
	if bucketFromEnv != "" {
		shared.BucketName = bucketFromEnv
		logger.Info("Bucket name:", bucketFromEnv)
	} else {
		logger.Infof("Bucket id not specified or empty, falling back to %s", shared.BucketName)
	}
	repoFromEnv := os.Getenv("REPO_PREFIX")
	if repoFromEnv != "" {
		shared.RepoDir = repoFromEnv
		logger.Info("Repo prefix in OSS:", repoFromEnv)
	} else {
		logger.Infof("Repo prefix in OSS is not specified in empty, falling back to %s", shared.RepoDir)
	}

	repoPath := filepath.Join(shared.MntPoint, shared.RepoDir)

	if len(event.Events) > 1 {
		logger.Error("More than two events received, I can't handle them:", event.Events)
		return rawEvents, errors.New(fmt.Sprintf("Expecting 1 event, received %d", len(event.Events)))
	}

	// Connect to OSS.
	logger.Info("Connecting to OSS using endpoint: " + "oss-" + ctx.Region + "-internal.aliyuncs.com")
	client, err := oss.New("oss-"+ctx.Region+"-internal.aliyuncs.com", credentials.AccessKeyID, credentials.AccessKeySecret, oss.SecurityToken(credentials.SecurityToken))
	if err != nil {
		logger.Error("Failed to connect to OSS:", err)
		return rawEvents, err
	} else {
		logger.Info("Successfully connected to OSS!")
	}

	// Connect to bucket.
	bucket, err := client.Bucket(shared.BucketName)
	if err != nil {
		logger.Error("Failed to connect to OSS bucket:", err)
		return rawEvents, err
	}

	// Get the (relative) path of the package.
	obj := event.Events[0].Oss.Object
	pkgPath := obj.Key
	nasPkgPath := filepath.Join(shared.MntPoint, *pkgPath)

	logger.Debug("Event:", *event.Events[0].EventName)

	if *event.Events[0].EventName == "ObjectRemoved:DeleteObject" {
		logger.Info("Cleaning package...")

		if err := shared.DeleteFile(nasPkgPath); err != nil {
			logger.Error("Failed to remove package", pkgPath, "at", nasPkgPath, ":", err)
			return rawEvents, err
		}
	} else if *event.Events[0].EventName == "ObjectRemoved:DeleteObjects" {
		logger.Warn("FC doesn't receive the full list of objects deleted when using ObjectRemoved:DeleteObjects. Checking every file in NAS...")

		err := shared.Clean(bucket, shared.MntPoint)
		if err != nil {
			logger.Error("Failed to clean orphaned packages:", err)
			return rawEvents, err
		}
	} else {
		logger.Info("Downloading package...")

		// Create the corresponding location in NAS if it doesn't exist.
		err = os.MkdirAll(filepath.Dir(nasPkgPath), 00755)
		if err != nil {
			logger.Error("Failed to create path for package in NAS:", err)
			return rawEvents, err
		}

		// Download object from OSS to NAS.
		err = bucket.GetObjectToFile(*pkgPath, nasPkgPath)
		if err != nil {
			logger.Error("Failed to download package from OSS:", err)
			return rawEvents, err
		}
	}

	err = shared.IndexDir(repoPath, ctx)
	if err != nil {
		logger.Error("Failed to index packages:", err)
		return rawEvents, err
	}

	logger.Info("Uploading index back to OSS bucket...")
	for _, file := range shared.IndexFiles {
		ossPath := filepath.Join(shared.RepoDir, file)
		nasPath := filepath.Join(repoPath, file)

		err = bucket.PutObjectFromFile(ossPath, nasPath)
		if err != nil {
			return rawEvents, err
		}
	}
	logger.Info("All files uploaded!")

	return rawEvents, nil
}

func main() {
	gr.Start(HandleRequest, nil)
}
