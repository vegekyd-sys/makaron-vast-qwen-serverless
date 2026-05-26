from vastai import Worker, WorkerConfig, HandlerConfig, BenchmarkConfig, LogActionConfig


MODEL_SERVER_URL = "http://127.0.0.1"
MODEL_SERVER_PORT = 18000
MODEL_LOG_FILE = "/var/log/makaron-qwen/comfyui.log"


def constant_workload(_payload: dict) -> float:
    return 100.0


worker_config = WorkerConfig(
    model_server_url=MODEL_SERVER_URL,
    model_server_port=MODEL_SERVER_PORT,
    model_log_file=MODEL_LOG_FILE,
    handlers=[
        HandlerConfig(
            route="/warmup",
            allow_parallel_requests=False,
            max_queue_time=900.0,
            workload_calculator=constant_workload,
            benchmark_config=BenchmarkConfig(
                dataset=[{}],
                runs=1,
                concurrency=1,
            ),
        ),
        HandlerConfig(
            route="/generate",
            allow_parallel_requests=False,
            max_queue_time=900.0,
            workload_calculator=constant_workload,
        ),
        HandlerConfig(
            route="/health",
            allow_parallel_requests=True,
            max_queue_time=30.0,
            workload_calculator=lambda _payload: 1.0,
        ),
    ],
    log_action_config=LogActionConfig(
        on_load=[
            "To see the GUI go to:",
        ],
        on_error=[
            "Traceback (most recent call last):",
            "RuntimeError:",
            "ERROR:",
            "Error occurred when executing",
        ],
        on_info=[
            "[qwen-server]",
            "got prompt",
        ],
    ),
)


Worker(worker_config).run()

