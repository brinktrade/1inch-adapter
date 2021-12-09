const hre = require('hardhat')
const { ethers } = require('hardhat')
const { expect } = require('chai')
const brinkUtils = require('@brinkninja/utils')
const { MAX_UINT_256, BN } = brinkUtils

const DAI_WHALE = '0xe78388b4ce79068e89bf8aa7f218ef6b9ab0e9d0'
const WETH_ADDRESS = '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
const DAI_ADDRESS = '0x6b175474e89094c44da98b954eedeac495271d0f'

const ETH_ADDRESS = '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE'

// Agg calldata for transfering 100000 DAI to WETH
const daiToWethCallData = '0x2e95b6c80000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b6d0340c3d03e4f041fd4cd388c549ee2a29a9e5075882fcfee7c08'


describe('tokenToToken', function () {
  beforeEach(async function () {
    const OneInchAdapter = await ethers.getContractFactory('OneInchAdapter')
    this.dai = await ethers.getContractAt('IERC20', DAI_ADDRESS)
    this.weth = await ethers.getContractAt('IERC20', WETH_ADDRESS)
    this.accountAddress = '0xa2884fB9F79D7060Bcfaa0e7D8a25b7F725de2fa'
    this.adapterOwnerAddress = '0xaf6FF32810E7215d17d7645e356E1e9001C3A446'
    this.adapter = await OneInchAdapter.deploy(this.adapterOwnerAddress)

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [DAI_WHALE],
    })
    const daiWhale = await hre.ethers.getSigner(DAI_WHALE)
    await this.dai.connect(daiWhale).transfer(this.adapter.address, '100000')
  })

  describe('token to token', function () {
    it('should swap DAI to WETH', async function () {
      const initialDaiBalance = await this.dai.balanceOf(this.adapter.address)
      const initialWethBalance = await this.weth.balanceOf(this.accountAddress)

      await this.adapter.oneInchSwap(daiToWethCallData, DAI_ADDRESS, '100000', WETH_ADDRESS, '10', this.accountAddress)

      const finalDaiBalance = await this.dai.balanceOf(this.adapter.address)
      const finalWethBalance = await this.weth.balanceOf(this.accountAddress)

      expect(finalWethBalance.eq(initialWethBalance.add(BN('10')))).to.equal(true)
      expect(finalDaiBalance.eq(initialDaiBalance.sub(BN('100000')))).to.equal(true)
    })
  })

  // describe('eth to token', function () {
  //   it('should swap ETH to DAI', async function () {
  //     await this.adapter.oneInchSwap(daiToWethCallData, ETH_ADDRESS, '1', DAI_ADDRESS, '2', this.accountAddress)
  //     console.log(await this.dai.balanceOf(this.adapter.address))
  //   })
  // })
})

async function sendEth(sender, to, value) {
  const res = await sender.sendTransaction({ to, value })
  return res
}