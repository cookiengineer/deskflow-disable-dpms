package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	binName := filepath.Base(os.Args[0])

	logPath := fmt.Sprintf("/tmp/%s.log", binName)
	realPath := fmt.Sprintf("/usr/bin/%s.real", binName)

	logEntry(logPath, binName)
	runReal(realPath)
}

func logEntry(logFile, binName string) {
	f, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()

	// Header if empty
	stat, err := f.Stat()
	if err == nil && stat.Size() == 0 {
		header := "TIME | BIN | PID | PPID | ARGS | PARENT_CMD | DISPLAY | XAUTHORITY\n"
		f.WriteString(header)
	}

	now := time.Now().Format(time.RFC3339)
	pid := os.Getpid()
	ppid := os.Getppid()

	args := strings.Join(os.Args, " ")
	parentCmd := readCmdline(ppid)

	display := os.Getenv("DISPLAY")
	xauth := os.Getenv("XAUTHORITY")

	line := fmt.Sprintf("%s | %s | %d | %d | %s | %s | %s | %s\n",
		now, binName, pid, ppid, args, parentCmd, display, xauth)

	f.WriteString(line)
}

func readCmdline(pid int) string {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	if err != nil {
		return "N/A"
	}

	clean := bytes.ReplaceAll(data, []byte{0}, []byte{' '})
	return strings.TrimSpace(string(clean))
}

func runReal(realPath string) {
	cmd := exec.Command(realPath, os.Args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	_ = cmd.Run()
}
