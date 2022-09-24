package shared

import (
	"os/exec"

	gr "github.com/awesome-fc/golang-runtime"
)

func IndexDir(dir string, ctx *gr.FCContext) error {
	logger := ctx.GetLogger()

	args := []string{"index", dir}
	output, err := exec.Command("moss", args...).Output()

	if err != nil {
		logger.Error("Command [ moss", args, "]couldn't run normally, error:", output)
		return err
	}

	return nil
}
