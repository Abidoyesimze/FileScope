const hre = require("hardhat");

async function main() {
    try {
        console.log(" Starting deployment process...\n");

        const [deployer] = await hre.ethers.getSigners();
        console.log(" Deploying with account:", deployer.address);
        console.log("Network:", hre.network.name);

        // Deploy the contract
        console.log("\n Deploying FileScopeRegistry contract...");
        const FileScopeRegistry = await hre.ethers.getContractFactory("FileScopeRegistry");
        const fileScopeRegistry = await FileScopeRegistry.deploy();
        await fileScopeRegistry.waitForDeployment();

        const fileScopeRegistryAddress = await fileScopeRegistry.getAddress();
        console.log("\n Contract deployed successfully!");
        console.log(" Contract address:", fileScopeRegistryAddress);

        // Wait for a few blocks before verification
        console.log("\n Waiting for 5 blocks before verification...");
        await new Promise(resolve => setTimeout(resolve, 30000));

        // Verify the contract
        console.log("\n Verifying contract on block explorer...");
        try {
            await hre.run("verify:verify", {
                address: vaultAddress,
                constructorArguments: []
            });
            console.log(" Contract verified successfully!");
        } catch (error) {
            console.error(" Contract verification failed:", error.message);
            console.log("\n Manual Verification Info:");
            console.log("Contract Address:", vaultAddress);
            console.log("Solidity Version: 0.8.20");
            console.log("Optimizer: Enabled with 200 runs");
            console.log("EVM Version: paris");
            console.log("No constructor arguments");
        }

        console.log("\n✨ Deployment process completed!");
    } catch (error) {
        console.error("\n Deployment failed:", error.message);
        if (error.stack) {
            console.error("Stack trace:", error.stack);
        }
        process.exit(1);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });