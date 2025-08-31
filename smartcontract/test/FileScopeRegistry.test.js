const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FileScopeRegistry", function () {
  let fileScopeRegistry;
  let owner;
  let user;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    const FileScopeRegistry = await ethers.getContractFactory("FileScopeRegistry");
    fileScopeRegistry = await FileScopeRegistry.deploy();
    await fileScopeRegistry.waitForDeployment(); 
  });

  it("should allow a user to upload a dataset", async function () {
    const cid = "QmABC123";
    const aiResult = "Sample AI analysis";
    const isPublic = true;

    await fileScopeRegistry.connect(user).uploadDataset(cid, aiResult, isPublic);

    const dataset = await fileScopeRegistry.getDataset(cid);

    expect(dataset.cid).to.equal(cid);
    expect(dataset.owner).to.equal(user.address);
    expect(dataset.aiAnalysis).to.equal(aiResult);
    expect(dataset.isPublic).to.equal(true);
    expect(dataset.views).to.equal(0);
    expect(dataset.downloads).to.equal(0);
    expect(dataset.citations).to.equal(0);
  });
});
