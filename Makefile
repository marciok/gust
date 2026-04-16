
dev:
	mix phx.server

test:
	mix test

test-cover:
	MIX_ENV=test mix coveralls.html --umbrella

lint:
	mix lint

console:
	iex -S mix
