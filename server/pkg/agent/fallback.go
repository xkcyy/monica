package agent

import (
	"context"
	"log/slog"
	"sync"
)

const maxFallbackAttempts = 5

type fallbackBackend struct {
	base           Backend
	primaryModel   string
	fallbackModels []string
	logger         *slog.Logger
}

func WithModelFallback(backend Backend, primaryModel string, fallbackModels []string, logger *slog.Logger) Backend {
	if logger == nil {
		logger = slog.Default()
	}
	return &fallbackBackend{
		base:           backend,
		primaryModel:   primaryModel,
		fallbackModels: fallbackModels,
		logger:         logger,
	}
}

func (fb *fallbackBackend) Execute(ctx context.Context, prompt string, opts ExecOptions) (*Session, error) {
	allModels := append([]string{fb.primaryModel}, fb.fallbackModels...)
	if len(allModels) > maxFallbackAttempts {
		allModels = allModels[:maxFallbackAttempts]
	}

	var lastErr error
	var mergedUsage = make(map[string]TokenUsage)

	for i, model := range allModels {
		isFallback := i > 0

		if isFallback {
			fb.logger.Info("trying fallback model",
				"attempt", i+1,
				"model", model,
				"primary_model", fb.primaryModel,
			)
			optsCopy := opts
			optsCopy.Model = model
			optsCopy.ResumeSessionID = ""
			opts = optsCopy
		} else {
			opts.Model = model
		}

		session, err := fb.base.Execute(ctx, prompt, opts)
		if err != nil {
			fb.logger.Warn("model execution returned error, trying fallback",
				"model", model,
				"error", err,
			)
			lastErr = err
			continue
		}

		result, ok := <-session.Result
		if !ok {
			fb.logger.Warn("result channel closed unexpectedly, trying fallback",
				"model", model,
			)
			lastErr = err
			continue
		}

		if fb.needsFallback(result.Status) {
			fb.logger.Warn("model execution failed status, trying fallback",
				"model", model,
				"status", result.Status,
				"error", result.Error,
			)
			lastErr = &FallbackError{Model: model, Status: result.Status, Err: result.Error}
			for k, v := range result.Usage {
				mergedUsage[k] = v
			}
			continue
		}

		for k, v := range result.Usage {
			mergedUsage[k] = v
		}
		result.Usage = mergedUsage

		return &Session{
			Messages: session.Messages,
			Result:   fb.wrapResult(session.Result, mergedUsage),
		}, nil
	}

	return nil, lastErr
}

func (fb *fallbackBackend) wrapResult(resultChan <-chan Result, mergedUsage map[string]TokenUsage) <-chan Result {
	out := make(chan Result, 1)
	go func() {
		defer close(out)
		result, ok := <-resultChan
		if ok {
			result.Usage = mergedUsage
			out <- result
		}
	}()
	return out
}

func (fb *fallbackBackend) needsFallback(status string) bool {
	return status == "failed" || status == "timeout" || status == "aborted"
}

func mergeTokenUsage(a, b TokenUsage) TokenUsage {
	return TokenUsage{
		InputTokens:      a.InputTokens + b.InputTokens,
		OutputTokens:     a.OutputTokens + b.OutputTokens,
		CacheReadTokens:  a.CacheReadTokens + b.CacheReadTokens,
		CacheWriteTokens: a.CacheWriteTokens + b.CacheWriteTokens,
	}
}

type FallbackError struct {
	Model  string
	Status string
	Err    string
}

func (e *FallbackError) Error() string {
	return "fallback model failed: model=" + e.Model + ", status=" + e.Status + ", error=" + e.Err
}

type resultMerger struct {
	mu      sync.Mutex
	usage   map[string]TokenUsage
	result  Result
	receved bool
}

func newResultMerger() *resultMerger {
	return &resultMerger{
		usage: make(map[string]TokenUsage),
	}
}

func (rm *resultMerger) addUsage(model string, usage TokenUsage) {
	rm.mu.Lock()
	defer rm.mu.Unlock()
	rm.usage[model] = usage
}

func (rm *resultMerger) mergeAndSend(result Result, out chan<- Result) {
	rm.mu.Lock()
	defer rm.mu.Unlock()

	for k, v := range result.Usage {
		if existing, ok := rm.usage[k]; ok {
			rm.usage[k] = mergeTokenUsage(existing, v)
		} else {
			rm.usage[k] = v
		}
	}
	result.Usage = rm.usage

	select {
	case out <- result:
	default:
	}
}
