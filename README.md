# aq-demo-rails

A stock Rails 8 application showing two CI workflows side by side: vanilla GitHub Actions vs [aq](https://github.com/pirj/aq) snapshots + 3-shard fan-out.

## What's in the suite

- 35 gem dependencies, 150 gems in `Gemfile.lock` (Devise, Sidekiq, ahoy_matey, Ransack, paper_trail, etc.)
- 9 migrations across 5 models (Post, Comment, User, Category, Tag) plus ahoy's visits/events
- 14 unit / controller / model tests
- 50 system tests (3 specific scenarios + 47 parameterized index loads via headless Chromium)
- RuboCop omakase

## CI workflows

| Workflow | Trigger | Bundler cache | Notes |
|---|---|---|---|
| [![CI (vanilla)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-vanilla.yml/badge.svg)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-vanilla.yml) | every push | `bundler-cache: true` | The "happy path" GitHub Actions setup. Ruby+Postgres+Chrome are pre-installed on `ubuntu-latest`. |
| [![CI (vanilla cold)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-vanilla-cold.yml/badge.svg)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-vanilla-cold.yml) | manual | OFF | Realistic for self-hosted runners or any setup without action-cache: every run does a fresh `bundle install`. |
| [![CI (aq)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-aq.yml/badge.svg)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-aq.yml) | every push | n/a | aq Alpine VM. First run bootstraps + provisions + snapshots; later runs restore from cache and `aq fanout 3` runs rubocop / minitest / system tests in parallel. |
| [![CI (aq fanout=8)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-aq-fanout8.yml/badge.svg)](https://github.com/pirj/aq-demo-rails/actions/workflows/ci-aq-fanout8.yml) | manual | n/a | Demonstrates fan-out parallelism: 8 isolated chromium-driven test shards launched concurrently from one snapshot. |

## Measured timings

Median wall-clock from GitHub Actions runs on `ubuntu-latest` (7 GB RAM, 2 vCPU, x86_64 KVM):

| Scenario | Duration | What's happening |
|---|---:|---|
| Vanilla (warm bundler-cache) | **65 s** | `setup-ruby` restores 150 gems from cache (~10 s) + sequential rubocop + 14 minitest + 50 system tests |
| Vanilla cold (cache miss) | **82 s** | Fresh `bundle install` of 150 gems (~25 s) + the same sequential test pipeline |
| aq warm (snapshot cache hit) | **87 s** | Restore aq's snapshot from `actions/cache` + `aq fanout 3` running rubocop + minitest + system tests in parallel inside one Alpine VM each |
| aq cold (snapshot cache miss) | **231 s** | Fresh Alpine bootstrap + full provision (apk add ruby/postgres/chromium, bundle install, db:setup) + snapshot save + fanout |
| aq fanout=8 (manual) | **102 s** | 8 parallel chromium browsers, each in its own VM, each running a slice of the system-test suite. fanout=50 OOMs on `ubuntu-latest` (50 × 1 GB > 7 GB). |

## Honest reading

- **On a stable Gemfile + GH-hosted runner with bundler-cache, vanilla wins on wall clock.** The reason is mundane: ubuntu-latest already ships Ruby, Postgres, and Chromium pre-installed; bundler-cache restores 150 gems in ~10 s. There's almost nothing for aq to compete with.
- **When the bundler-cache misses, vanilla takes ~82 s — virtually identical to aq warm at ~87 s.** This is the regime where aq's snapshot acts as a structural equivalent of bundler-cache that *also* covers everything beyond the bundle (postgres init data, chromium binary, migrations applied, fixtures generated…).
- **Aq cold (231 s) is paid once per `(Gemfile.lock, db/schema.rb, Dockerfile, bin/aq-provision)` change.** Subsequent commits with no provisioning churn hit warm at ~87 s.

## Where aq wins, where it doesn't

**Wins:**
- **Self-hosted / sandbox CI without action-cache infrastructure.** Vanilla cold = 82 s on every run; aq warm = 87 s with snapshot cache restored from any blob store you control.
- **Cold-start scenarios with frequent dependency churn.** Each Gemfile change rebuilds the bundler-cache from scratch on vanilla; on aq the first run after the change is slow but every subsequent push hits warm.
- **Multi-stack provisioning beyond gems.** Postgres, Redis, Chromium, image-processing libs, npm/yarn for assets — aq's snapshot is one cache, vanilla needs a separate caching strategy per layer.
- **True parallelism with full isolation.** `aq fanout 8` launches 8 chromium browsers each in its own VM with its own Postgres. No shared globals, no port conflicts, no test-order dependencies. Vanilla's parallelization is in-process (Rails parallelize) which can't isolate at the OS level.
- **Memory ceiling**: GitHub-hosted runners have 7 GB RAM. 50 chromium browsers ≈ 10 GB → OOM with vanilla parallel testing. Aq fanout = 50 also OOMs on `ubuntu-latest` (50 × 1 GB VM); fanout = 8 fits and scales gracefully on bigger self-hosted hardware.

**Doesn't win:**
- A simple Rails app on `ubuntu-latest` with `bundler-cache: true`. The vanilla path is genuinely fast there.
- Workflows where `bin/rails test:system` is the only meaningful step. aq's per-VM startup overhead outweighs the parallelism gain on tiny suites.

## Architecture: the aq workflow

```
push → checkout
     → install qemu / socat / ovmf            (apt cache)
     → install aq + tio                        (binary cache)
     → compute snapshot key = sha256(Gemfile.lock, db/schema.rb, Dockerfile, bin/aq-provision)
     → restore alpine base                     (actions/cache)
     → restore snapshot                        (actions/cache; key tied to alpine base version)

if snapshot cache MISS (i.e. provisioning inputs changed):
     aq new app
     aq start app                              ← ssh keypair from repo (deterministic)
     aq scp -r . app:/repo
     aq exec app /repo/bin/aq-provision        ← apk add ruby chromium postgres; bundle install; db:setup
     aq stop app
     aq snapshot create app provisioned        ← snapshot saved to actions/cache at job end

(always)
     aq new --from-snapshot=provisioned staging
     aq start staging
     aq scp -r . staging:/repo                  ← push current source over the cached state
     aq stop staging
     aq snapshot create staging running-with-code
     aq fanout running-with-code 3 -- 'case $AQ_SHARD_INDEX in
       0) bundle exec rubocop ;;
       1) RAILS_ENV=test bin/rails test ;;
       2) RAILS_ENV=test bin/rails test:system ;;
     esac'
```

## Try it locally

```sh
brew install qemu tio socat                 # macOS
# or, on Linux:
sudo apt install qemu-system-x86 socat ovmf

git clone https://github.com/pirj/aq && export PATH=$PWD/aq:$PATH
git clone https://github.com/pirj/aq-demo-rails && cd aq-demo-rails

aq new app
aq start app
aq scp -r . app:/repo
aq exec app /repo/bin/aq-provision
aq stop app
aq snapshot create app provisioned
aq rm app

aq fanout provisioned 3 -- '
  cd /repo
  case $AQ_SHARD_INDEX in
    0) bundle exec rubocop ;;
    1) RAILS_ENV=test bin/rails test ;;
    2) RAILS_ENV=test bin/rails test:system ;;
  esac
'
```

## Notes on what this demo does *not* show

- **The full aq cold path** (apt install qemu, alpine bootstrap from ISO, setup-alpine, bundle install, db migrations) takes ~4 minutes. On a stable repo that path runs once per `(Gemfile.lock, db/schema.rb, Dockerfile, bin/aq-provision)` change. Real production CI usually amortises this over many commits.
- **Snapshot transport cost**: actions/cache moves the ~480 MB snapshot blob between the runner and GitHub's blob storage. Same-region transfers help; cross-region could dominate.
- **OOM behaviour at high N**: `ubuntu-latest` has 7 GB RAM. Each aq VM defaults to 1 GB. So `aq fanout 50` on a hosted runner does not fit; on a self-hosted box with 64 GB RAM it does. KSM dedup of read-only snapshot pages helps but doesn't eliminate the per-VM working set.

## License

MIT.
