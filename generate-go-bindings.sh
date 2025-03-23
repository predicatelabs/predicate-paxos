#!/bin/bash

binding_dir="./gen/bindings"

function create_binding {
    contract=$1
    echo "Generating bindings for" $contract

    # Assuming your compiled contract JSON is in the out directory
    contract_json="./out/${contract}.sol/${contract}.json"
    solc_abi=$(cat ${contract_json} | jq -r '.abi')
    solc_bin=$(cat ${contract_json} | jq -r '.bytecode.object')

    mkdir -p data
    echo ${solc_abi} >data/tmp.abi
    echo ${solc_bin} >data/tmp.bin

    rm -f $binding_dir/${contract}/binding.go
    mkdir -p $binding_dir/${contract}
    abigen --bin=data/tmp.bin --abi=data/tmp.abi --pkg=${contract} --out=$binding_dir/${contract}/binding.go
    rm -rf data/tmp.abi data/tmp.bin
    rm -f tmp.abi tmp.bin
}

# Clean and build the contracts
forge clean
forge build --via-ir

# Generate bindings for your contract

create_binding "ISimpleV4Router"
