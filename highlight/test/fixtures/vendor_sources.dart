// Synthetic, public regression fixtures. No private evaluation samples.
const soliditySource = '''pragma solidity ^0.8.24;
contract Vault {
  mapping(address => uint256) public balance;
  event Deposit(address indexed sender, uint256 amount);
  function deposit() external payable {
    balance[msg.sender] += msg.value;
    emit Deposit(msg.sender, msg.value);
  }
  function read(bytes32 key) public view returns (uint256 value) {
    assembly {
      let slot := add(key, 1)
      { value := sload(slot) }
    }
  }
}
''';
const vueSource = '''<template>
  <button @click="count++">{{ count }}</button>
</template>
<script setup lang="ts">
import { ref } from 'vue';
const count: number = ref(0);
</script>
<style scoped lang="scss">
button { color: red; &:hover { color: blue; } }
</style>
''';
const javascriptSource = '''function greet(name) {
  const items = [1, 2, 3];
  items.push(name.length);
  console.log("hello", name);
  return items.map(x => x + 1);
}
''';
const goSource = '''package main
import "fmt"
func main() {
  values := []int{1, 2, 3}
  for _, value := range values {
    fmt.Println(value)
  }
}
''';
