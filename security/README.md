# Security gates (reference, Spar C)

Technical reference for the Spar C ("DevSecOps & kvalitet") track — see
`kursplan.md` in the course repo root, and the student lab guide in
`course-material/labs/spar-c-devsecops.md` for the step-by-step version in
Swedish.

This directory holds the deliberately vulnerable demo image, and the
`.trivyignore.yaml` the gate reads sits in the repo root — both ship with the
template. The gate workflows themselves do not: they live in
`course-material/templates/spar-c/` and are copied into `../.github/` when
you start the track.

## Where the gates sit

```
  PR opened
      |
      +-- ci.yml            ruff + pytest                       (M5)
      +-- security.yml      Trivy on images built from the PR   <-- gate 1
      +-- codeql.yml        CodeQL on our own source            <-- gate 2
      |                     (both are Spar C files — this repo ships
      |                      neither; copy them in from
      |                      course-material/templates/spar-c/)
      |
   merge to main  (branch protection makes the above required)
      |
      +-- publish-images.yml   build + push to GHCR             (M6)
              |
              v
          deploy.yml   (Spar C version — this repo ships the one-job M9
              |         deploy; copy it in from
              |         course-material/templates/spar-c/)
              |
              +-- scan-images       Trivy on the PUBLISHED images   <-- gate 3
              +-- deploy-dev        environment: dev, no approval
              +-- integration-test  black-box HTTP against dev      <-- gate 4
              +-- deploy-prod       environment: prod, HUMAN APPROVAL
```

Plus Dependabot, which runs on a schedule rather than in the pipeline and
opens pull requests that then flow through all of the above — also a Spar C
file (`dependabot.yml` in the same reference directory), for the same reason.

## Three scanners, three different questions

They get lumped together as "the security scanners". They are not
interchangeable, and a repo running only one of them has a specific,
predictable blind spot.

| | Question it answers | Whose bug | Finds it how |
|---|---|---|---|
| **Trivy** | Does this image contain a dependency with a *known* CVE? | Someone else's, already public | Lookup against a vulnerability database |
| **CodeQL** | Does the code *we wrote* contain an exploitable pattern? | Ours, nobody has ever seen it | Dataflow: untrusted source → dangerous sink |
| **Dependabot** | Is a newer version of this dependency available? | Nobody's yet | Watches upstream releases |

A repo with only Trivy ships hand-written SQL injection with a green
pipeline — no CVE exists for a bug you invented this morning. A repo with
only CodeQL ships a five-year-old vulnerable `urllib3` with a green pipeline
— that code is fine, it is just *old and publicly broken*. Dependabot is the
only one of the three that arrives with the fix already written, and when the
pipeline is working properly it is the reason the other two never go red: the
boring version-bump PR merged last Tuesday is what kept the CVE out.

## What blocks, and why that line is drawn at HIGH

The gate is `--severity HIGH,CRITICAL --exit-code 1`. MEDIUM and LOW findings
are still collected, uploaded as SARIF, and visible in the repo's Security
tab — they just do not stop anyone from merging.

The temptation is to block on everything. Resist it, for a reason that has
nothing to do with how dangerous MEDIUM findings are:

**A gate that fires constantly gets switched off.** Not by a decision anyone
writes down — by a Friday afternoon when the release is blocked on a MEDIUM
in a transitive dependency of a test-only library, and someone adds
`continue-on-error: true` "just for now". Six months later nobody remembers
the gate exists. The scanner still runs. It protects nothing.

So the severity threshold is not a claim that MEDIUM findings are harmless.
It is a budget. HIGH and CRITICAL are, roughly, "remote attacker gets code
execution or your data" — findings a team will genuinely stop for. Setting
the bar there keeps the number of stops low enough that each one is taken
seriously, which is the only property that makes a gate work at all.

The corollary matters just as much: **MEDIUM findings still have to be
looked at.** They go in the Security tab, not in the bin. The difference
between blocking and reporting is *who decides when to act* — for HIGH the
pipeline decides, for MEDIUM a human does.

## Why `--ignore-unfixed`

Trivy also reports vulnerabilities with no released patch. The gate filters
those out, and that is a scoping decision rather than a way to make the scan
quieter.

Think about who the gate is talking to. It is blocking a specific person's
pull request, and it is implicitly saying "fix this before you merge". If no
patch exists, that person's available moves are: rewrite the dependency
themselves, remove the feature, or turn the gate off. In practice it is
always the third one — see above.

Unfixed vulnerabilities are real and do need handling; they just need a
different mechanism, on a different timescale, aimed at a different person.
Changing base image, or accepting the risk with a review date, is an owner's
decision, not a blocker on an unrelated PR. Run the scan without the flag
periodically to see them:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.58.1 image --scanners vuln --severity HIGH,CRITICAL \
  template-app-backend
```

Note that `--ignore-unfixed` has a useful side effect on how you read a
finding: **anything the gate shows you has a fix available.** Which leads
directly to the next section.

## The remediation hierarchy: patch > ignore-with-expiry > accept

In that order, every time.

**1. Patch.** A fixed version exists → upgrade to it. This is not the
boring option, it is the *correct* option, and it is almost always cheaper
than the alternatives. The git history of `backend/requirements.txt` in this
repo is a worked example: the Spar C gate failed on the clean image because
`fastapi==0.115.6` pinned `starlette<0.42`, and `starlette 0.41.3` carried
three fixable HIGHs. The fix was one line — bump fastapi — and the test suite
proved in four seconds that nothing broke.

That pairing is the entire point. A dependency bump is a scary, deferred,
someday task in a repo with no tests, and a five-minute chore in a repo with
tests. Everything the course says about automated testing is upstream of
being able to patch quickly, and being able to patch quickly is what keeps
you out of the situation where the only remaining option is to argue that the
vulnerability doesn't apply to you.

**2. Ignore, with an expiry date.** Only for two situations, both documented
in `../.trivyignore.yaml`: the finding is not fixable in context (no patch,
or the patch needs a migration you cannot do today), or the vulnerable code
path is *provably* unreachable — a claim someone could disprove by pointing
at a line of code. Every entry carries a written statement and an
`expired_at` date, so the exception cannot outlive the reason for it.

**3. Accept.** Permanent risk acceptance. This is not a developer's call
during code review; it belongs to whoever owns the service.

The trap is between 1 and 2, and it is worth being blunt about it. Those
three starlette CVEs came with perfectly good-sounding arguments for
ignoring them: the SSRF is in `StaticFiles` and nginx serves our static
files; the Range-header DoS is behind a reverse proxy; the form-limits DoS
needs `request.form()`, which this app never calls. Every one of those
statements is true. Writing them into `.trivyignore.yaml` would have produced
a green pipeline and a well-documented decision — and the repo would still be
running known-vulnerable code, for no reason, because a patch existed the
whole time.

**When a fix exists, arguing about exploitability is a waste of the argument.**
Save it for the findings where you have no choice.

## False positives vs missed CVEs: the costs are not symmetric

A false positive costs one developer some minutes, in the open, with a
traceable decision at the end — someone investigates, concludes it does not
apply, and records why. Annoying, bounded, and it happens on a day when
everyone is paying attention.

A missed CVE costs an incident, at an unknown future time, discovered by
someone other than you.

Read naively that asymmetry says "block on everything, false positives are
cheap". It does not, because false positives are not independent events —
their real cost is not the minutes, it is what a *stream* of them does to the
gate's credibility. The first false positive gets investigated. The tenth
gets waved through. The thirtieth gets `continue-on-error`. Each individual
false positive is cheap; the erosion is what is expensive, and it converts
directly into missed CVEs later.

Which is why the tuning here is narrow rather than loose: block on a small,
high-confidence set (HIGH/CRITICAL, fixable), and put everything else where
it stays *visible* without being in anyone's way. The goal is a gate that is
red rarely, and believed completely when it is.

## Why the approval gate is before prod and not before dev

`deploy-dev` has no required reviewers. `deploy-prod` does. This is a
deliberate asymmetry.

Dev exists to be broken. Its whole value is that a change reaches a real,
running, deployed system fast — and that is where the integration tests get
to run against something real. Putting a human in front of it would add
latency to the feedback loop that is *supposed* to be fast, and it would do
something worse: it would train people to approve without reading. A reviewer
who clicks approve twenty times a week for dev is not going to read the
twenty-first one carefully because it happens to say prod.

The prod approval is the one place in the pipeline where a human is asked a
question a machine cannot answer. Not "does it pass?" — the scanners and
integration tests already answered that, which is why the approval prompt
only appears after all of them are green. The human question is about
*context*: is now a good time? Is this the change we think it is? Is anyone
around if it goes wrong? Machines have no opinion about deploying on a Friday
at 16:55.

That ordering — automate every question with a mechanical answer, then ask
the human the one that is left — is what keeps the approval meaningful. Put
the human first and they become a slow, unreliable linter. Put them last and
they are the only thing in the pipeline doing judgement.

And there is a second function, which is accountability. GitHub records who
approved which deploy. Not to blame them, but because "who decided this went
out" is the first question of every incident review, and a pipeline that
cannot answer it makes postmortems into archaeology.

## Running the blocking demo locally

No GitHub account and no cloud access needed — this is the same logic the CI
gate runs.

Build both images from the repo root:

```bash
docker build -t template-app-backend:clean backend
docker build -t template-app-backend:vulnerable \
  -f security/vulnerable-demo/Dockerfile backend
```

The only difference between them is one `pip install PyYAML==5.3.1` line.
Scan each:

```bash
for tag in clean vulnerable; do
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:0.58.1 image --scanners vuln --ignore-unfixed \
    --severity HIGH,CRITICAL --exit-code 1 "template-app-backend:$tag"
  echo "$tag -> exit $?"
done
```

Expected: `clean -> exit 0`, and `vulnerable -> exit 1` with
`CVE-2020-14343` (PyYAML, CRITICAL, arbitrary code execution via
`yaml.full_load`, fixed in 5.4) in the table. That non-zero exit code is the
entire mechanism — in CI, a step exiting non-zero fails the job, a failed
required check blocks the merge, and an unmerged change never reaches prod.

## This reference will go stale, on purpose

The scan results above were true on the day this was written. They will not
stay true: new CVEs are published against pinned dependencies constantly, and
`starlette 1.3.1` will have its own findings sooner or later.

That is not a defect in the reference, it is the actual working condition of
every real project. Do not treat a green scan as a property of this repo;
treat it as a measurement with a timestamp. When you run the scan and see
findings that are not documented here, that is the exercise, not a broken
lab — triage what is in front of you using the hierarchy above.
