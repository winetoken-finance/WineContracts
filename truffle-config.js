require("dotenv").config();
const HDWalletProvider = require("@truffle/hdwallet-provider");
const infuraAppKey = process.env.INFURAAPP;
const mnemonic = process.env.MNEMONIC;
module.exports = {
	networks: {
		development: {
			host: "127.0.0.1",
			port: 7545,
			network_id: "5777",
		},
		mainnet: {
			provider: () => new HDWalletProvider(mnemonic, `https://mainnet.infura.io/v3/${infuraAppKey}`),
			network_id: 1, // mainnet's id
			gas: 5500000,
			gasPrice: 87000000000,
			confirmations: 0, // # of confs to wait between deployments. (default: 0)
			timeoutBlocks: 500, // # of blocks before a deployment times out  (minimum/default: 50)
			skipDryRun: false, // Skip dry run before migrations? (default: false for public nets )
		},
		ropsten: {
			provider: () => new HDWalletProvider(mnemonic, `https://ropsten.infura.io/v3/${infuraAppKey}`),
			network_id: 3, // Ropsten's id
			gas: 5500000, // Ropsten has a lower block limit than mainnet
			gasPrice: 87000000000,
			confirmations: 0, // # of confs to wait between deployments. (default: 0)
			timeoutBlocks: 200, // # of blocks before a deployment times out  (minimum/default: 50)
			skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
		},
		rinkeby: {
			provider: () => new HDWalletProvider(mnemonic, `https://rinkeby.infura.io/v3/${infuraAppKey}`),
			network_id: 4, // Ropsten's id
			gas: 5500000, // Ropsten has a lower block limit than mainnet
			gasPrice: 135000000000,
			confirmations: 0, // # of confs to wait between deployments. (default: 0)
			timeoutBlocks: 200, // # of blocks before a deployment times out  (minimum/default: 50)
			skipDryRun: true, // Skip dry run before migrations? (default: false for public nets )
		},
		testnet: {
			provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545`),
			network_id: 97,
			confirmations: 1,
			timeoutBlocks: 200,
			skipDryRun: true
		  },
		  BSC: {
			provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed1.binance.org`),
			network_id: 56,
			confirmations: 1,
			timeoutBlocks: 200,
			skipDryRun: true
		  },
		advanced: {
			websockets: true, // Enable EventEmitter interface for web3 (default: false)
		},
	},
	contracts_build_directory: "../client/src/abis/",
	compilers: {
		solc: {
			version: "0.7.6",
			settings: {
				optimizer: {
					enabled: true,
					runs: 500,
				},
			},
		},
	},
};
