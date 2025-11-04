<template>
  <div id="app">
    <nav class="main-nav">
      <div class="nav-container">
        <div class="nav-brand">
          <h1>🧠 MSHH Solver</h1>
          <span class="nav-subtitle">Multi-Stage Hyper-Heuristic Framework</span>
        </div>
        <div class="nav-tabs">
          <button
            @click="currentView = 'single'"
            :class="{ active: currentView === 'single' }"
            class="nav-tab"
          >
            🎯 Single Solve
          </button>
          <button
            @click="currentView = 'batch'"
            :class="{ active: currentView === 'batch' }"
            class="nav-tab"
          >
            🚀 Batch Solve
          </button>
        </div>
      </div>
    </nav>

    <div class="app-content">
      <Solver v-if="currentView === 'single'" />
      <BatchSolver v-if="currentView === 'batch'" />
    </div>
  </div>
</template>

<script>
import { ref } from 'vue'
import Solver from './components/Solver.vue'
import BatchSolver from './components/BatchSolver.vue'

export default {
  name: 'App',
  components: {
    Solver,
    BatchSolver
  },
  setup() {
    const currentView = ref('single')

    return {
      currentView
    }
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
  margin: 0;
}

#app {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.main-nav {
  background: rgba(255, 255, 255, 0.98);
  box-shadow: 0 2px 16px rgba(0, 0, 0, 0.1);
  backdrop-filter: blur(10px);
  position: sticky;
  top: 0;
  z-index: 1000;
}

.nav-container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 20px 30px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 30px;
}

.nav-brand h1 {
  font-size: 24px;
  color: #2c3e50;
  margin: 0 0 5px 0;
}

.nav-subtitle {
  font-size: 12px;
  color: #7f8c8d;
  font-weight: normal;
}

.nav-tabs {
  display: flex;
  gap: 10px;
}

.nav-tab {
  padding: 12px 24px;
  border: 2px solid transparent;
  background: #f8f9fa;
  color: #34495e;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
}

.nav-tab:hover {
  background: #ecf0f1;
  transform: translateY(-2px);
}

.nav-tab.active {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border-color: transparent;
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
}

.app-content {
  flex: 1;
  padding: 30px 20px;
  overflow-y: auto;
}

/* Responsive */
@media (max-width: 768px) {
  .nav-container {
    flex-direction: column;
    align-items: flex-start;
    gap: 15px;
  }

  .nav-tabs {
    width: 100%;
  }

  .nav-tab {
    flex: 1;
    text-align: center;
  }
}
</style>
