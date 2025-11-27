# Gust

A task orchestration engine for Elixir applications.


---


### 🔨 Core Features

- [x] Cancel retrying tasks  
- [x] Restart task
- [x] Stop task manually
- [x] Add task run time tracking
- [x] Handle syntax errors during development
- [x] Handle corrupted task state
- [x] Fail hooks: email, Slack → Webhooks
- [x] Clear state (restart logic)
- [x] Add backoff jitter

### ⚠️ Still Needed

- [ ] Remove error from UI when task later succeeds (or hide it)
- [ ] Allow deletion of non-running runs
- [ ] Add timing for "running" state
- [ ] Add user accounts (authentication/authorization)
- [ ] Update or cancel scheduler when a task is changed
- [ ] Handle timeout-related run failures
- [ ] Reset UI page after manual trigger

---

## ✨ Nice to Have

- [ ] Animate background to reflect "running" state
- [ ] A polished, user-friendly UI

---

## 🏗️ Architecture Notes

- Enforce minimum test coverage via GitHub Actions
- Centralize updates to `task` and `run` in one place
- Use **atomic update operations** (`!` functions) for state changes

---

