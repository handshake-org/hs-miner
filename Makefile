all:
	@npm run install-main

main:
	@npm run install-main

testnet:
	@npm run install-testnet

regtest:
	@npm run install-regtest

simnet:
	@npm run install-simnet

clean:
	@npm run clean

lint:
	@npm run lint

test:
	@npm test

.PHONY: all main testnet simnet clean lint test
