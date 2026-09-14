all: compile

compile:
	mix $@

dev:
	mix phx.server

test:
	mix test $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

test-cover:
	MIX_ENV=test mix coveralls.html --umbrella

lint:
	mix lint

console:
	iex -S mix

run:
	iex -S mix phx.server
