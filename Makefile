all:
	@EXTRA_ARG=$(extra) npm run install-main $(cuda_path)

main:
	@EXTRA_ARG=$(extra) npm run install-main $(cuda_path)

testnet:
	@EXTRA_ARG=$(extra) npm run install-testnet $(cuda_path)

regtest:
	@EXTRA_ARG=$(extra) npm run install-regtest $(cuda_path)

simnet:
	@EXTRA_ARG=$(extra) npm run install-simnet $(cuda_path)

clean:
	@npm run clean

lint:
	@npm run lint

test:
	@npm test

.PHONY: all main testnet simnet clean lint test
