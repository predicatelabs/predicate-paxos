.PHONY: install build tests clean format deploy-router deploy-hook deploy-tokens-and-pool deploy-contracts 


DEPLOYER_ECDSA_PRIV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# public key - 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

RPC_URLS=http://localhost:8545,http://localhost:8545

COMMIT_HASH=$(shell git rev-parse --short HEAD)


#_______________________________________GETTING STARTED________________________________________#
install:
	git submodule update --init --recursive && git config --local core.hooksPath .githooks/ && chmod +x .githooks/pre-commit

tests:
	forge test --via-ir

clean:
	rm -rf ./out ./build

format:
	forge fmt 

build:
	forge build --via-ir

#_______________________________________LOCAL ENV SETUP_______________________________________#
deploy-pool-manager:
	forge script script/common/DeployPoolManager.s.sol \
		--via-ir \
		--rpc-url http://localhost:8545 \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-router:
	export NETWORK=LOCAL && \
	forge script script/common/DeploySimpleV4Router.s.sol \
		--via-ir \
		--rpc-url http://localhost:8545 \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-hook:
	export NETWORK=LOCAL && \
	forge script script/common/DeployPredicateHook.s.sol \
		--via-ir \
		--rpc-url http://localhost:8545 \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-tokens-and-pool:
	export NETWORK=LOCAL && \
	export HOOK_ADDRESS=0x18A5c776bdb3502C4172F8b5558281cf0060c080 && \
	forge script script/common/DeployTokensAndPool.s.sol \
		--via-ir \
		--rpc-url http://localhost:8545 \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-contracts: deploy-pool-manager deploy-router deploy-hook deploy-tokens-and-pool
