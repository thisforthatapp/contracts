# TFTV1Escrow Smart Contract

TFTV1Escrow is a decentralized escrow system built on Ethereum. It allows multiple participants to create trades, deposit assets (both ERC20 tokens and NFTs), and execute trades in a trustless manner.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Testing](#testing)
- [Deployment](#deployment)
- [Interacting with the Contract](#interacting-with-the-contract)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)
- [License](#license)

## Features

- Multi-party escrow system
- Support for both ERC20 tokens and NFTs
- Flat fee system for trade participation
- Admin controls for fee adjustment and recipient management
- Comprehensive test suite using Forge

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- [Node.js](https://nodejs.org/) and npm (for additional tooling if needed)
- An Ethereum wallet with some ETH for deployment and testing

## Installation

1. Clone the repository:

   ```
   git clone https://github.com/thisforthatapp/contracts
   cd contracts
   ```

2. Install dependencies:

   ```
   forge install
   ```

3. Set up your environment variables by creating a `.env` file:
   ```
   SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
   PRIVATE_KEY=your_wallet_private_key
   ETHERSCAN_API_KEY=your_etherscan_api_key
   ```

## Testing

Run the test suite using Forge:

```
forge test
```

For more verbose output:

```
forge test -vvv
```

## Deployment

1. Ensure your `.env` file is set up correctly.

2. Deploy to Sepolia testnet:

   ```
   forge script script/DeployTFTV1Escrow.s.sol:DeployTFTV1Escrow --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
   ```

3. Note the deployed contract address printed in the console.

## Interacting with the Contract

You can interact with the deployed contract using Foundry's `cast` command or by writing additional scripts.

### Examples:

1. Create a trade:

   ```
   cast send <CONTRACT_ADDRESS> "createTrade(address[])" "[<PARTICIPANT1>,<PARTICIPANT2>]" --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

2. Deposit an asset:

   ```
   cast send <CONTRACT_ADDRESS> "depositAsset(uint256,address,uint256,uint256,bool)" <TRADE_ID> <TOKEN_ADDRESS> <TOKEN_ID> <AMOUNT> <IS_NFT> --value <FEE_AMOUNT> --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

3. Confirm a trade:
   ```
   cast send <CONTRACT_ADDRESS> "confirmTrade(uint256)" <TRADE_ID> --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```

### Running the Interaction Script

To run a full trade scenario:

1. Update the `InteractWithTFTV1Escrow.s.sol` script with your deployed contract address.
2. Run the script:
   ```
   forge script script/InteractWithTFTV1Escrow.s.sol:InteractWithTFTV1Escrow --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
   ```

## Security Considerations

- Always handle private keys securely and never commit them to version control.
- Thoroughly test the contract in various scenarios before deploying to mainnet.
- Consider getting a professional audit before using the contract with real assets.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
