const { ethers } = require('hardhat')
const snapshot = require('snap-shot-it')
const { expect } = require('chai')
const deploySaltedBytecode = require('@brinkninja/core/test/helpers/deploySaltedBytecode')
const {
  ADAPTER_OWNER,
  ONE_INCH_ADAPTER
} = require('../constants')

describe('OneInchAdapter.sol', function () {
    it('deterministic address check', async function () {
      const OneInchAdapter = await ethers.getContractFactory('OneInchAdapter')
      const address = await deploySaltedBytecode(OneInchAdapter.bytecode, ['address'], [ADAPTER_OWNER])
      snapshot(address)
      expect(address, 'Deployed account address and ONE_INCH_ADAPTER constant are different').to.equal(ONE_INCH_ADAPTER)
    })
  })