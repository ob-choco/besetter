FROM python:3.10-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /code

COPY ./pyproject.toml ./uv.lock /code/

RUN uv sync --frozen --no-dev

COPY ./app /code/app

ENTRYPOINT ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
