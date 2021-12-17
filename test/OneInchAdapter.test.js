const hre = require('hardhat')
const { ethers } = hre
const { expect } = require('chai')
const brinkUtils = require('@brinkninja/utils')
const { randomHex, toChecksumAddress } = require('web3-utils')
const { MAX_UINT_256, BN } = brinkUtils
const snapshotGas = require('./helpers/snapshotGas')
const setupAdapterOwner = require('./helpers/setupAdapterOwner')

const DAI_WHALE = '0xe78388b4ce79068e89bf8aa7f218ef6b9ab0e9d0'
const WETH_ADDRESS = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
const DAI_ADDRESS = '0x6b175474e89094c44da98b954eedeac495271d0f'
const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'

// 100000000000000000000 wei 
const ONE_HUNDRED = '100000000000000000000'

// Agg calldata for transfering 100 DAI to WETH
const daiToWethCallData = '0x2e95b6c80000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000002cc11fa6b521e30000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b6d0340c3d03e4f041fd4cd388c549ee2a29a9e5075882fcfee7c08'

// Agg calldata for transfering 100 DAI to ETH
const daiToEthCallData = '0x2e95b6c80000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000002bf5e837c7b7fc0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000140000000000000003b6d0340c3d03e4f041fd4cd388c549ee2a29a9e5075882fcfee7c08'

// Agg calldata fro transfering 100 ETH to DAI
const ethtoDaiCallData = '0xe449022e0000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000002a48bd487f28b7740a9f00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000002c0000000000000000000000088e6a0c2ddd26feeb64f039a2c41296fcb3f56408000000000000000000000005777d92f208679db4b9778590fa3cab3ac9e2168cfee7c08'


describe('oneInchSwap', function () {
  beforeEach(async function () {
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [DAI_WHALE],
    })
    const daiWhale = await hre.ethers.getSigner(DAI_WHALE)

    // Initialize the contracts
    const OneInchAdapter = await ethers.getContractFactory('OneInchAdapter')
    this.dai = (await ethers.getContractAt('IERC20', DAI_ADDRESS)).connect(daiWhale)
    this.weth = await ethers.getContractAt('IERC20', WETH_ADDRESS)
    this.accountAddress = '0xa2884fB9F79D7060Bcfaa0e7D8a25b7F725de2fa'
    this.adapterOwner = await setupAdapterOwner()
    this.adapter = await OneInchAdapter.deploy()
    this.adapter_asOwner = (await OneInchAdapter.deploy()).connect(this.adapterOwner)

    // Send DAI to OneInchAdapter
    await this.dai.transfer(this.adapter.address, ONE_HUNDRED)
  })

  describe('token to token', function () {
    it('should swap DAI to WETH', async function () {
      const initialDaiBalance = await this.dai.balanceOf(this.adapter.address)
      const initialWethBalance = await this.weth.balanceOf(this.accountAddress)

      await this.adapter.oneInchSwap(daiToWethCallData, DAI_ADDRESS, ONE_HUNDRED, WETH_ADDRESS, '10', this.accountAddress)

      const finalDaiBalance = await this.dai.balanceOf(this.adapter.address)
      const finalWethBalance = await this.weth.balanceOf(this.accountAddress)

      expect(finalWethBalance.eq(initialWethBalance.add(BN('10')))).to.equal(true)
      expect(finalDaiBalance.eq(initialDaiBalance.sub(BN(ONE_HUNDRED)))).to.equal(true)
    })

    it('gas cost', async function () {
      await snapshotGas(await this.adapter.oneInchSwap(daiToWethCallData, DAI_ADDRESS, ONE_HUNDRED, WETH_ADDRESS, '10', this.accountAddress))
    })
  })

  describe('eth to token', function () {
    it('should swap ETH to DAI', async function () {
      const initialDaiBalance = await this.dai.balanceOf(this.accountAddress)
      const initialEthBalance = await ethers.provider.getBalance(this.adapter.address);

      const overrides = {
        value: ethers.utils.parseEther("100.0") //sending 100 ether with call
      }
      await this.adapter.oneInchSwap(ethtoDaiCallData, ETH_ADDRESS, ONE_HUNDRED, DAI_ADDRESS, '10', this.accountAddress, overrides)

      const finalDaiBalance = await this.dai.balanceOf(this.accountAddress)
      const finalEthBalance = await ethers.provider.getBalance(this.adapter.address);

      expect(finalDaiBalance.eq(initialDaiBalance.add(BN('10')))).to.equal(true)
      expect(finalEthBalance.eq(initialEthBalance)).to.equal(true)
    })

    it('gas cost', async function () {
      const overrides = {
        value: ethers.utils.parseEther("100.0") //sending 100 ether with call
      }
      await snapshotGas(await this.adapter.oneInchSwap(ethtoDaiCallData, ETH_ADDRESS, ONE_HUNDRED, DAI_ADDRESS, '10', this.accountAddress, overrides))
    })
  })

  describe('token to eth', function () {
    it('should swap DAI to ETH', async function () {
      const initialEthBalance = await ethers.provider.getBalance(this.accountAddress);
      const initialDaiBalance = await this.dai.balanceOf(this.adapter.address)

      await this.adapter.oneInchSwap(daiToEthCallData, DAI_ADDRESS, ONE_HUNDRED, ETH_ADDRESS, '10', this.accountAddress)

      const finalEthBalance = await ethers.provider.getBalance(this.accountAddress);
      const finalDaiBalance = await this.dai.balanceOf(this.adapter.address)

      expect(finalEthBalance.eq(initialEthBalance.add(BN('10')))).to.equal(true)
      expect(finalDaiBalance.eq(initialDaiBalance.sub(BN(ONE_HUNDRED)))).to.equal(true)
    })

    it('gas cost', async function () {
      await snapshotGas(await this.adapter.oneInchSwap(daiToEthCallData, DAI_ADDRESS, ONE_HUNDRED, ETH_ADDRESS, '10', this.accountAddress))
    })
  })

  describe('Withdrawable', function () {
    beforeEach(async function () {
      this.defaultSigner = (await ethers.getSigners())[0]
      this.recipientAddr = randomAddress()
      await this.dai.transfer(this.adapter_asOwner.address, BN('10000000000000000000000'))
      await sendEth(this.defaultSigner, this.adapter_asOwner.address, BN('10000000000000000000000000'))
    })

    it('should allow owner to withdraw ETH', async function () {
      const iBalance = await ethers.provider.getBalance(this.recipientAddr)
      await this.adapter_asOwner.withdrawEth('1000', this.recipientAddr)
      const fBalance = await ethers.provider.getBalance(this.recipientAddr)
      expect(fBalance.sub(iBalance)).to.equal(BN('1000'))
    })

    it('should allow owner to withdraw token', async function () {
      const iBalance = await this.dai.balanceOf(this.recipientAddr)
      await this.adapter_asOwner.withdrawToken(this.dai.address, '1000', this.recipientAddr)
      const fBalance = await this.dai.balanceOf(this.recipientAddr)
      expect(fBalance.sub(iBalance)).to.equal(BN('1000'))
    })

    it('should revert if non-owner calls withdrawEth()', async function () {
      await expect(this.adapter.withdrawEth('1000', this.recipientAddr))
        .to.be.revertedWith('Ownable: caller is not the owner')
    })

    it('should revert if non-owner calls withdrawToken()', async function () {
      await expect(this.adapter.withdrawToken(this.dai.address, '1000', this.recipientAddr))
        .to.be.revertedWith('Ownable: caller is not the owner')
    })
  })
})

async function sendEth(sender, to, value) {
  const res = await sender.sendTransaction({ to, value })
  return res
}

const randomAddress = () => toChecksumAddress(randomHex(20))
