# DELIBERATELY VULNERABLE IMAGE — teaching artifact, never deployed.
#
# This exists so the Spar C blocking gate can be demonstrated on a laptop,
# with no GitHub account and no cloud access: build this image, scan it,
# watch Trivy exit non-zero. See ../README.md and the lab guide
# (course-material/labs/spar-c-devsecops.md).
#
# Build and scan from the repo root:
#
#   docker build -t template-app-backend:vulnerable \
#     -f security/vulnerable-demo/Dockerfile backend
#
#   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
#     aquasec/trivy:0.58.1 image --scanners vuln --ignore-unfixed \
#     --severity HIGH,CRITICAL --exit-code 1 \
#     template-app-backend:vulnerable
#
#   echo $?    # -> 1. In CI that non-zero exit IS the gate.
#
# Note the build context is `backend`, not the repo root — this file starts
# from the real backend image so the ONLY difference between the image that
# passes and the image that fails is the one line below.
FROM python:3.12-slim

# Same OS-package patch layer as backend/Dockerfile — keeps the diff between
# this image and the real one at EXACTLY one line (the PyYAML pin below), so
# the scan contrast stays clean vs vulnerable, not patched vs unpatched base.
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# The whole demo, on one line.
#
# PyYAML 5.3.1 carries CVE-2020-14343: arbitrary code execution through
# yaml.full_load() on untrusted input. CRITICAL, published in 2021, fixed in
# 5.4. It was chosen for three reasons:
#
#   1. CRITICAL and unambiguous — nobody has to argue about the severity.
#   2. Five years old with a released fix, so it will not quietly disappear
#      from the database or become "unfixed" and get filtered by
#      --ignore-unfixed. The demo still works next year.
#   3. It is a DOWNGRADE, not an addition: the real image already contains
#      PyYAML 6.x, pulled in transitively by uvicorn[standard]. Nobody adds a
#      2021 CVE to a project on purpose — they pin a transitive dependency to
#      "the version that worked" and never look at it again. That is the
#      realistic failure this is imitating.
#
# In the pull-request version of this demo you add the same line to
# backend/requirements.txt on a throwaway branch instead. Do NOT commit that
# to main, and do not leave the branch lying around.
RUN pip install --no-cache-dir PyYAML==5.3.1

COPY app ./app
COPY tests ./tests

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
