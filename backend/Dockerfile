FROM python:3.12-slim

# Patch OS packages at build time: fixable CVEs land in the base image
# continuously and upstream doesn't always rebuild on the same day. The
# Spar C Trivy gate blocks fixable HIGH/CRITICAL findings, so patching
# here (before app layers, so it caches separately) is the first step of
# the remediation hierarchy — see .trivyignore.yaml.
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
COPY pyproject.toml .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY tests ./tests

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
