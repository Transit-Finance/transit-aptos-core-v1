## contract compile and publish
```angular2html
compile:
aptos move compile --save-metadata

publish:
aptos move publish --url https://fullnode.mainnet.aptoslabs.com/v1 

```

## init contract event resource
```angular2html
payload: {
  function: '0x325d9eea7124e04da8b8e755c867daa2d37792194492af98127a77b1baeefd06::aggregator::init_module_event',
  type_arguments: [],
  arguments: [],
  type: 'entry_function_payload'
}
```