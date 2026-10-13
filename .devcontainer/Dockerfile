FROM mcr.microsoft.com/devcontainers/python:3.12

# Pinned CLI versions for the course toolchain (terraform, kubectl, oc, flux, gh, k6, openstack).
# Bump these deliberately when the course needs a newer version.
ARG TERRAFORM_VERSION=1.15.8
ARG KUBECTL_VERSION=v1.36.3
ARG FLUX_VERSION=2.9.3
ARG GH_VERSION=2.97.0
# TARGETARCH is auto-populated by buildx (amd64 on Codespaces/CI, arm64 on
# Apple Silicon) — do NOT give it a default value here, that would shadow
# the real value and always resolve to whatever the default says.
ARG K6_VERSION=2.1.0
ARG OPENSTACKCLIENT_VERSION=10.2.1
# Node.js + npm-installed AI CLIs (TASK-254): students use these directly in
# Codespaces without installing anything themselves. No API keys/tokens are
# baked in anywhere below — each tool prompts for its own login on first run.
ARG NODE_VERSION=24.19.0
ARG CLAUDE_CODE_VERSION=2.1.226
ARG CODEX_CLI_VERSION=0.147.0
ARG GEMINI_CLI_VERSION=0.54.4
ARG TARGETARCH

# openssh-client: ssh/scp to the cPouta VM in M7 (deploy manually, then via Actions in M9).
# unzip: needed below to unpack the Terraform release archive.
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-client \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Terraform: M8, provisions the cPouta VM as code (HashiCorp release zip).
RUN curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
    && unzip -q /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip

# kubectl: talks to any Kubernetes API, incl. Rahti (OpenShift is a k8s distro).
RUN curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# oc: OpenShift-specific CLI (login, routes, projects) for CSC Rahti (track B).
# The mirror names the amd64 build "linux" (no arch suffix) and arm64 "linux-arm64".
RUN OC_ARCH_SUFFIX="" \
    && if [ "${TARGETARCH}" = "arm64" ]; then OC_ARCH_SUFFIX="-arm64"; fi \
    && curl -fsSL -o /tmp/oc.tar.gz \
        "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux${OC_ARCH_SUFFIX}.tar.gz" \
    && tar -xzf /tmp/oc.tar.gz -C /usr/local/bin oc \
    && rm /tmp/oc.tar.gz

# flux: bootstraps/inspects the FluxInstance GitOps sync on Rahti (track B).
RUN curl -fsSL -o /tmp/flux.tar.gz \
        "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/flux.tar.gz -C /usr/local/bin flux \
    && rm /tmp/flux.tar.gz

# gh: GitHub CLI — repo creation (track B's manifest repo) and PR work from
# the terminal. No token baked in; students run `gh auth login` themselves.
RUN curl -fsSL -o /tmp/gh.tar.gz \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}"

# k6: load-testing the app (interpret CPU/mem/latency under load), track C.
RUN curl -fsSL -o /tmp/k6.tar.gz \
        "https://github.com/grafana/k6/releases/download/v${K6_VERSION}/k6-v${K6_VERSION}-linux-${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/k6.tar.gz -C /tmp \
    && mv /tmp/k6-v${K6_VERSION}-linux-${TARGETARCH}/k6 /usr/local/bin/k6 \
    && rm -rf /tmp/k6.tar.gz /tmp/k6-v${K6_VERSION}-linux-${TARGETARCH}

# openstack: M8 network lookups (network_name) and the M7/M8 floating-ip/quota
# commands in iac/terraform/README.md — python-openstackclient, via pip since
# the base image already has Python.
RUN pip install --no-cache-dir "python-openstackclient==${OPENSTACKCLIENT_VERSION}"

# Node.js: the python devcontainer base image ships no JS runtime, and the AI
# CLIs below are npm packages. nodejs.org names amd64 builds "x64".
RUN NODE_ARCH="${TARGETARCH}" \
    && if [ "${TARGETARCH}" = "amd64" ]; then NODE_ARCH="x64"; fi \
    && curl -fsSL -o /tmp/node.tar.gz \
        "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
    && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.gz

# AI coding CLIs (TASK-254): Claude Code, OpenAI Codex CLI, Gemini CLI — the
# course's core AI-assistant list. Installed globally, no credentials baked
# in; each authenticates interactively on first run in the student's own
# session. GitHub Copilot CLI, aider and opencode were evaluated and skipped:
# each pulls 130-680MB more (aider drags in a full Python ML stack — numpy,
# scipy, tokenizers) on top of what the three core tools already add, for
# capability that overlaps with Claude Code/Codex/Gemini.
RUN npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@openai/codex@${CODEX_CLI_VERSION}" \
        "@google/gemini-cli@${GEMINI_CLI_VERSION}" \
    && npm cache clean --force
