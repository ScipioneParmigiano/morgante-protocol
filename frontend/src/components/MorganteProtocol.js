import React, { useState, useEffect } from 'react'
import { ethers } from 'ethers'
import protocolAbi from '../abi/src_Pool_sol_FlashLoan.json'
import collateralAbi from '../abi/collateralAbi.json'
import MorganteAbi from '../abi/src_MordredToken_sol_Mordred.json'
import './MorganteProtocol.css'
import {
    NumberInput,
    NumberInputField,
    Button,
    Center,
    Stack,
    Text,
} from '@chakra-ui/react'
/* global BigInt */

const MorganteProtocol = () => {
    let MorganteProtocolAddressSepolia = '0x2b4cEf96b24f968Ae0bddf6C7CF4BA0CBddFA4Ba';

    let linkSepoliaAddress = '0x7e2f41F9b08AC139bc02b420D9ed07D7ea13BdE1';
    let wbtcSepoliaAddress = '0x2dB3483bb42eb115A50bC0f2FF61bDfa4f919D19';

    const [currentContractFee, setCurrentContractFee] = useState(null);
    const [provider, setProvider] = useState(null);
    const [signer, setSigner] = useState(null);
    const [contract, setContract] = useState(null);
    const [networkId, setNetworkId] = useState('');
    const [defaultAccount, setDefaultAccount] = useState(null);
    const [errorMessage, setErrorMessage] = useState(null);
    const [userBalance, updateUserBalance] = useState(0);
    const [userBalanceMorgante, updateUserMorganteBalance] = useState(0);
    const [userAddress, setUserAddress] = useState(null);
    const [isConnected, setIsConnected] = useState(false);
    const [pageState, setPageState] = useState(false);
    const [selectedToken, setselectedToken] = useState('');
    const [userRewards, setUserRewards] = useState(0);


    const handleOptionClick = (option) => {
        console.log(option)
        setselectedToken(option);
        setPageState(true);
    };

    const connectWalletHandler = async () => {
        if (isConnected) {
            return;
        }

        if (window.ethereum) {
            try {
                await window.ethereum.request({ method: 'eth_requestAccounts' });

                const provider = new ethers.BrowserProvider(window.ethereum);
                const network = await provider.getNetwork();
                setNetworkId(network.chainId);
                setIsConnected(true);
            } catch (error) {
                console.error('Error connecting to MetaMask:', error);
            }
        } else {
            console.error('MetaMask not detected. Please install MetaMask.');
            setErrorMessage('Please install MetaMask browser extension to interact');
        }

        updateEthers();
        console.log(contract)
        setUserAddress(window.ethereum.selectedAddress);
    };

    useEffect(() => {
        async function checkConnectedWallet() {
            if (window.ethereum && window.ethereum.selectedAddress) {
                setUserAddress(window.ethereum.selectedAddress);
                setIsConnected(true);
            }
        }
        async function getUserBalance() {

            if (selectedToken === 'LINK') {
                let val = await contract.getUserBalanceSingularToken(signer, linkSepoliaAddress)
                console.log(String(parseInt(val) / 1e18) + ' ' + selectedToken)
                updateUserBalance(String(parseInt(val) / 1e18));
            }

            if (selectedToken === 'wBTC') {
                let val = await contract.getUserBalanceSingularToken(signer, wbtcSepoliaAddress)
                console.log(String(parseInt(val) / 1e8) + ' ' + selectedToken)
                updateUserBalance(String(parseInt(val) / 1e8));
            }
        }

        async function getUserBalanceMorgante() {
            if (isConnected && selectedToken === 'LINK') {
                let val = await contract.getmddAmountOwned(signer)
                console.log(val)

                updateUserMorganteBalance(String(parseInt(val) / 1e18));
            }

            if (isConnected && selectedToken === 'wBTC') {
                let val = await contract.getmddAmountOwned(signer)
                console.log(val)

                updateUserMorganteBalance(String(parseInt(val) / 1e18));
            }
        }

        async function updateRewards() {

            if (selectedToken === 'LINK') {
                let val = await contract.getUserRewards(linkSepoliaAddress);
                console.log(val)

                setUserRewards(String(parseInt(val) / 1e18));
            }

            if (selectedToken === 'wBTC') {
                let val = await contract.getUserRewards(wbtcSepoliaAddress);
                console.log(val)

                setUserRewards(String(parseInt(val) / 1e8));
            }
        }



        checkConnectedWallet();

        if (isConnected) {
            getUserBalance();
            getUserBalanceMorgante(); //aggiungere la funzione ???
            updateRewards();
        }
    });

    useEffect(() => {
        if (isConnected) {
            updateEthers()
        }
    }, [])

    const accountChangedHandler = (newAccount) => {
        setDefaultAccount(newAccount);
        setUserAddress(newAccount[0]);
        updateEthers();
    }

    const chainChangedHandler = () => {
        window.location.reload();
    }


    window.ethereum.on('chainChanged', chainChangedHandler);

    window.ethereum.on('accountsChanged', accountChangedHandler);

    const updateEthers = async () => {
        console.log('updating ethers')

        let tempProvider = new ethers.BrowserProvider(window.ethereum);
        setProvider(tempProvider);

        let tempSigner = await tempProvider.getSigner();
        setSigner(tempSigner);

        const network = await tempProvider.getNetwork();

        if (network.chainId === 534351n) {
            let tempContract = new ethers.Contract(MorganteProtocolAddressSepolia, protocolAbi, tempSigner);
            setContract(tempContract)
        }
    }

    const deposit = async (event) => {
        event.preventDefault();

        // updateEthers();
        // console.log("updated")
        console.log(await contract.getTokenAddresses())
        let MordredeAddress = await contract.returnMordredEngineAddress();
        console.log(MordredeAddress)

        if (selectedToken === 'LINK') {
            let link = new ethers.Contract(linkSepoliaAddress, collateralAbi, signer);
            let tx = await link.approve(MordredeAddress, ethers.parseEther(event.target.amountCollateral.value))

            await tx.wait()

            await contract.deposit(ethers.parseEther(event.target.amountCollateral.value), ethers.parseEther(event.target.amountMordredToMint.value), linkSepoliaAddress);
        }

        // console.log(networkId)

        if (selectedToken === 'wBTC') {
            // console.log((ethers.parseEther(event.target.amountMordredToMint.value)))
            // console.log((ethers.parseEther(event.target.amountCollateral.value) / BigInt(1e8)))
            let wbtc = new ethers.Contract(wbtcSepoliaAddress, collateralAbi, signer);
            let tx = await wbtc.approve(MordredeAddress, ethers.parseEther(event.target.amountCollateral.value) / BigInt(1e10))
            await tx.wait()
            console.log("types")

            // await contract.deposit(1000000n, 1n, wbtcSepoliaAddress);

            await contract.deposit(ethers.parseEther(event.target.amountCollateral.value) / BigInt(1e10), ethers.parseEther(event.target.amountMordredToMint.value), wbtcSepoliaAddress);
            console.log("types 2")
        }

        console.log("nulla")
    }

    const redeem = async (event) => {
        event.preventDefault();

        // await updateEthers();

        let MordredeAddress = await contract.returnMordredEngineAddress();
        let MorganteAddress = await contract.returnMordredTokenAddress();
        let Morgante = new ethers.Contract(MorganteAddress, MorganteAbi, signer);

        console.log('approving')
        let tx = await Morgante.approve(MordredeAddress, ethers.parseEther(event.target.amountMordredToBurn.value))
        console.log('approved')
        await tx.wait()

        if (selectedToken === 'LINK') {
            console.log('withdrawing ' + event.target.amountCollateral.value + ' ' + String(selectedToken) + ' from the protocol and burning ' + event.target.amountMordredToBurn.value + ' Mordred');
            await contract.withdraw(linkSepoliaAddress, ethers.parseEther(event.target.amountCollateral.value), ethers.parseEther(event.target.amountMordredToBurn.value));
        }

        if (selectedToken === 'wBTC') {
            console.log('withdrawing ' + event.target.amountCollateral.value + ' ' + String(selectedToken) + ' from the protocol and burning ' + event.target.amountMordredToBurn.value + ' Mordred');
            await contract.withdraw(wbtcSepoliaAddress, ethers.parseEther(event.target.amountCollateral.value) / BigInt(1e10), ethers.parseEther(event.target.amountMordredToBurn.value));
        }
    }

    const claimRewards = async (event) => {
        event.preventDefault();
        console.log('claiming rewards');

        if (selectedToken === 'LINK') {
            await contract.claimReward(linkSepoliaAddress);
        }

        if (selectedToken === 'wBTC') {
            await contract.claimReward(wbtcSepoliaAddress);
        }
    }

    const getCurrentFee = async () => {
        let newFee = await contract.getFee();
        let precision = await contract.getPrecision();
        let netFee = Math.round(((parseFloat(newFee) / parseFloat(precision)) * 100 - 100) * 100) / 100;
        setCurrentContractFee(netFee.toString() + '%');
        console.log(currentContractFee)
    }

    return (
        <div>
            <button class='metamaskConnect' onClick={connectWalletHandler}>
                {isConnected ? String(userAddress).substring(0, 10) + '...' : 'Connect Wallet'}
            </button><hr />
            <Text color={'gray.500'}>
                Choose between LINK and wBTC as the collateral to deposit and/or withdraw, mint and burn your Mordred and start earning a yield today!
            </Text>
            <Center>
                <Stack spacing={{ base: 4, sm: 6 }} direction={{ base: 'column', sm: 'row' }}>
                    <Button
                        className={selectedToken === 'LINK' ? 'selected' : ''}
                        onClick={() => handleOptionClick('LINK')}
                        rounded={'full'}
                        size={'lg'}
                        fontWeight={'normal'}
                        px={6}
                        colorScheme={'red'}
                        bg={'red.400'}
                        _hover={{ bg: 'red.500' }}>
                        LINK
                    </Button>
                    <Button
                        className={selectedToken === 'wBTC' ? 'selected' : ''}
                        onClick={() => handleOptionClick('wBTC')}
                        rounded={'full'}
                        size={'lg'}
                        fontWeight={'normal'}
                        px={6}
                        colorScheme={'red'}
                        bg={'red.400'}
                        _hover={{ bg: 'red.500' }}>
                        wBTC
                    </Button>
                </Stack>
            </Center>
            <Center>
                <h5>{pageState ? 'You deposited ' + userBalance + ' ' + String(selectedToken) : 'Select a token to see your collateral balance'}</h5>
                {errorMessage}
            </Center>
            <Center>
                <h5>{pageState ? 'You own ' + userBalanceMorgante + ' ' + 'Mordred' : 'Select a token to see your Mordred balance'}</h5>
                {errorMessage}
            </Center>
            <hr>
            </hr>
            <Text color={'gray.500'}>
                Deposit and/or withdraw {selectedToken}, mint and burn your Mordred tokens, paying attention to the liquidability of your position. Also remember that you can't deposit, redeem, mint or burn a null quantity of tokens.
            </Text>
            <div>
                <dir>
                    <Center mt={1}>
                        <Stack direction="row" spacing={4}>
                            <form onSubmit={deposit}>
                                <NumberInput size='xs' maxW={60} defaultValue={0.5} min={0.000000000000000002} id='amountCollateral'>
                                    <NumberInputField />
                                </NumberInput>
                                <NumberInput size='xs' maxW={60} defaultValue={10} min={0.000000000000000001} id='amountMordredToMint'>
                                    <NumberInputField />
                                </NumberInput>
                                <Button
                                    rounded={'full'}
                                    size={'lg'}
                                    fontWeight={'normal'}
                                    px={6}
                                    colorScheme={'red'}
                                    bg={'red.400'}
                                    _hover={{ bg: 'red.500' }}
                                    type={'submit'}> {'Deposit ' + String(selectedToken)} </Button>
                            </form>
                            <form onSubmit={redeem}>
                                <NumberInput size='xs' maxW={60} defaultValue={0.1} min={0.000000000000000002} id='amountCollateral'>
                                    <NumberInputField />
                                </NumberInput>
                                <NumberInput size='xs' maxW={60} defaultValue={100} min={0.000000000000000001} id='amountMordredToBurn'>
                                    <NumberInputField />
                                </NumberInput>
                                <Button
                                    type={'submit'}
                                    rounded={'full'}
                                    size={'lg'}
                                    fontWeight={'normal'}
                                    px={6}
                                    colorScheme={'red'}
                                    bg={'red.400'}
                                    _hover={{ bg: 'red.500' }}> {'Redeem ' + String(selectedToken)} </Button>
                            </form>
                        </Stack>
                    </Center>
                </dir>
            </div>
            <hr />
            <div>
                <Text color={'gray.500'}>
                    Claim your rewards once a flash loan has occurred! Note that the portocol doesn't use the fees collected, therefore we strongly encourage you to claim your rewards and reinvest them.
                </Text>
                <Center>
                    <h5>{pageState ? 'Your rewards are: ' + userRewards + ' ' + String(selectedToken) : 'Select a token to claim your rewards'}</h5>
                </Center>
            </div>
            <Center>
                <Button
                    type={'submit'}
                    rounded={'full'}
                    size={'lg'}
                    fontWeight={'normal'}
                    px={6}
                    colorScheme={'red'}
                    bg={'red.400'}
                    onClick={claimRewards}>
                    Claim rewards
                </Button>
            </Center>
        </div>
    );
}

export default MorganteProtocol;
