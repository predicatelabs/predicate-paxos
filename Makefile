.PHONY: install build tests clean format deploy-router deploy-hook create-pool-and-mint-liquidity deploy-auto-wrapper deploy-contracts swap-usdc-for-usdl-exact-in swap-usdl-for-usdc-exact-in swap-usdl-for-usdc-exact-out

DEPLOYER_ECDSA_PRIV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
# public key - 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

PREDICATE_HOOK_ADDRESS=0x452e2E2CfcaC437d4E321226A3255d2cFc5c68A0
SWAP_ROUTER_ADDRESS=0x8F2c925603c4ba055779475F14241E3c9ee7c1be
AUTO_WRAPPER_HOOK_ADDRESS=0x75202124c8B7FAFBD66AB67F39CE01f69C0128c8
POSM_ADDRESS=0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e # mainnet POSM
# POLICY_ID=x-aleo-6a52de9724a6e8f2 // mainnet
POLICY_ID=local-test-policy

# Network configuration
NETWORK=MAINNET
RPC_URL=http://localhost:8545

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

#______________________________________ENV SETUP_______________________________________#
deploy-pool-manager:
	forge script script/common/DeployPoolManager.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-router:
	export NETWORK=${NETWORK} && \
	forge script script/common/DeployV4SwapRouter.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-predicate-hook:
	export NETWORK=${NETWORK} && \
	export SWAP_ROUTER_ADDRESS=${SWAP_ROUTER_ADDRESS} && \
	export POLICY_ID=${POLICY_ID} && \
	export POSM_ADDRESS=${POSM_ADDRESS} && \
	forge script script/common/DeployPredicateHook.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

create-pool-and-mint-liquidity:
	export NETWORK=${NETWORK} && \
	export HOOK_ADDRESS=${PREDICATE_HOOK_ADDRESS} && \
	export SWAP_ROUTER_ADDRESS=${SWAP_ROUTER_ADDRESS} && \
	forge script script/common/CreatePoolandMintLiquidity.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-auto-wrapper:
	export NETWORK=${NETWORK} && \
	export HOOK_ADDRESS=${PREDICATE_HOOK_ADDRESS} && \
	export SWAP_ROUTER_ADDRESS=${SWAP_ROUTER_ADDRESS} && \
	forge script script/common/DeployAutoWrapperAndInitPool.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

deploy-contracts: deploy-pool-manager deploy-router deploy-predicate-hook create-pool-and-mint-liquidity deploy-auto-wrapper

#______________________________________SWAP SCRIPT_______________________________________#
swap-usdc-for-usdl-exact-in:
	export NETWORK=${NETWORK} && \
	export CASE=SWAP_USDC_FOR_USDL_EXACT_IN && \
	export AUTO_WRAPPER_HOOK_ADDRESS=${AUTO_WRAPPER_HOOK_ADDRESS} && \
	export SWAP_ROUTER_ADDRESS=${SWAP_ROUTER_ADDRESS} && \
	forge script script/common/SwapScript.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

swap-usdl-for-usdc-exact-in:
	export NETWORK=${NETWORK} && \
	export CASE=SWAP_USDL_FOR_USDC_EXACT_IN && \
	export AUTO_WRAPPER_HOOK_ADDRESS=${AUTO_WRAPPER_HOOK_ADDRESS} && \
	export SWAP_ROUTER_ADDRESS=${SWAP_ROUTER_ADDRESS} && \
	forge script script/common/SwapScript.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv

swap-usdl-for-usdc-exact-out:
	export NETWORK=${NETWORK} && \
	export CASE=SWAP_USDL_FOR_USDC_EXACT_OUT && \
	export AUTO_WRAPPER_HOOK_ADDRESS=${AUTO_WRAPPER_HOOK_ADDRESS} && \
	export SWAP_ROUTER_ADDRESS=${SWAP_ROUTER_ADDRESS} && \
	forge script script/common/SwapScript.s.sol \
		--via-ir \
		--rpc-url ${RPC_URL} \
		--private-key ${DEPLOYER_ECDSA_PRIV_KEY} \
		--broadcast -vvvv


