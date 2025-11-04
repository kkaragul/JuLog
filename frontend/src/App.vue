<template>
  <div id="app">
    <Solver />
  </div>
</template>

<script>
import Solver from './components/Solver.vue'

export default {
  name: 'App',
  components: {
    Solver
  }
}
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
  padding: 20px;
}

#app {
  min-height: 100vh;
}
</style>
