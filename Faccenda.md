next steps:

* integrate with token swap:
    * missing the fee in the swap;
    * integrate the swap in pool.sol
    * swap contract should be broadcasted
    * tokenswap contract should be only the interfacte and should interact directly with mordredEngine (so that we don't need to change the liquidation threeshold and the whole collateral provided can be used to mint MDD)
* collect rewards function has to be changed, as well as deposit and redeem
* tests and correct readme.md
* deploy and VERIFY (on sepolia.scrollscan.dev)
* last check
* deploy dapp (spheron?)
* video and presentation of the protocol
* submission


sistemare constructor di mockswapprot e mdde nel deploy