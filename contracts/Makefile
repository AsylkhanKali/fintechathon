# Autonomous Treasury — contracts. Every token here is a zero-value test token.
-include .env
export

# Anvil's default dev accounts #0 (owner) and #1 (agent): public, zero value, local only.
ANVIL_OWNER := 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ANVIL_AGENT := 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
CONTRACTS   := Treasury MockUSDC MockYieldVault MockPriceFeed
VERIFY      := $(if $(ETHERSCAN_API_KEY),--verify --etherscan-api-key $(ETHERSCAN_API_KEY),)

.PHONY: build test coverage abi anvil deploy-local seed-local deploy-base-sepolia seed-base-sepolia

build:
	forge build

test:
	forge test

coverage:
	forge coverage --report summary --no-match-coverage "(script|test)"

abi: build
	@mkdir -p abi
	@for c in $(CONTRACTS); do forge inspect $$c abi --json > abi/$$c.json; done
	@echo "ABIs written to abi/"

anvil:
	anvil

deploy-local:
	AGENT_ADDRESS=$(ANVIL_AGENT) forge script script/Deploy.s.sol --rpc-url anvil --broadcast --unlocked --sender $(ANVIL_OWNER)

seed-local:
	forge script script/SeedDemo.s.sol --rpc-url anvil --broadcast --unlocked --sender $(ANVIL_OWNER)

deploy-base-sepolia:
	forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --private-key $(OWNER_PRIVATE_KEY) $(VERIFY)

seed-base-sepolia:
	forge script script/SeedDemo.s.sol --rpc-url base_sepolia --broadcast --private-key $(OWNER_PRIVATE_KEY)
