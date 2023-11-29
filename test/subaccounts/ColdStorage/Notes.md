# Challenges

1. owner account is executor

   - not possible to use registry

2. owner account could be Ownable owner (Kernel, Safe)

   - need new kernel fallback manager

3. Executor Module

   - basically a backdoor. would we actually attest to that on the registry?
   - needs conditions
     - timelock condition?
     - other

4. Hook

   - incompatible between accounts
     - hook on executor? insufficient security
     - hook in account? incompatible. Safe Guard only?

5. Validator

   - validator added to subaccount
     - what is it validating? ERC1271 to owner?
     - owner == sender?

6. does it actually make sense to build this right now?
   - needs complete rewrite for miniMSA
