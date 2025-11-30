# Decentralized StableCoin (DSC)

A minimal, decentralized, algorithmic stablecoin system pegged to USD.

## About

This project implements a stablecoin system designed to be a flatcoin (pegged to USD) but decentralized and censorship-resistant.

Key properties:
1.  **Exogenous Collateral:** Backed by crypto assets (WETH and WBTC).
2.  **Dollar Pegged:** 1 DSC is designed to maintain a value of $1 USD.
3.  **Algorithmically Stable:** Uses a minting and burning mechanism combined with liquidation incentives to maintain the peg and solvency.

The system is always **overcollateralized**. At no point should the value of all collateral be less than or equal to the dollar-backed value of all circulating DSC.

## Architecture

-   **`DecentralizedStableCoin.sol`**: An ERC20 implementation of the stablecoin. It is "Burnable" and "Ownable", where the owner is the `DSCEngine` contract.
-   **`DSCEngine.sol`**: The core logic contract handling:
    -   **Collateral Management:** Depositing and redeeming WETH/WBTC.
    -   **Minting/Burning:** Users can mint DSC if they have sufficient collateral.
    -   **Liquidation:** If a user's Health Factor drops below 1, liquidators can repay the user's debt (burn DSC) and seize their collateral with a 10% bonus.
    -   **Price Feeds:** Uses Chainlink Data Feeds to fetch real-time prices for collateral assets.

## Getting Started

### Requirements

-   [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
-   [foundry](https://getfoundry.sh/) (Forge, Cast, Anvil, Chisel)
-   [make](https://www.gnu.org/software/make/)

### Installation

1.  Clone the repository:
    ```bash
    git clone <repo-url>
    cd DecentralizedStablecoin
    ```
2.  Install dependencies:
    ```bash
    make install
    ```

## Usage

### Build

Compile the contracts:

```bash
make build
```

### Testing

Run the comprehensive test suite, including unit and invariant tests:

```bash
make test
```

To see test coverage:

```bash
make coverage
```

### Deployment

#### Local Deployment (Anvil)

1.  Start a local Anvil chain in a separate terminal:
    ```bash
    make anvil
    ```
2.  Deploy the contracts to the local chain:
    ```bash
    make deploy
    ```

#### Testnet Deployment (Sepolia)

1.  Create a `.env` file in the root directory and add your keys:
    ```env
    SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY
    PRIVATE_KEY=YOUR-PRIVATE-KEY
    ETHERSCAN_API_KEY=YOUR-ETHERSCAN-KEY
    ```
2.  Deploy to Sepolia:
    ```bash
    make deploy ARGS="--network sepolia"
    ```

## Future Improvements

1.  **Governance System:** Implement a DAO structure (e.g., using Governor Bravo) to allow token holders to vote on protocol parameters like liquidation thresholds, bonuses, and allowed collateral types.
2.  **Stability Fees:** Introduce a borrowing fee (stability fee) to generate revenue for the protocol and manage DSC supply more effectively.
3.  **Multi-Collateral Support:** Expand the list of accepted collateral tokens beyond WETH and WBTC.
4.  **Oracle Redundancy:** Integrate multiple oracle providers or a TWAP (Time-Weighted Average Price) mechanism to mitigate the risk of a single oracle failure.
5.  **Emergency Functions:** Add `pause` functionality or an "Emergency Shutdown" mode (similar to MakerDAO's Global Settlement) to protect funds in case of critical vulnerabilities or market crashes.
6.  **Frontend Interface:** Build a user-friendly DApp for users to easily interact with the protocol (deposit, mint, redeem, liquidate).

## License

MIT
