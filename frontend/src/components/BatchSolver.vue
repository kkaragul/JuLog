<template>
  <div class="batch-solver">
    <div class="header">
      <h2>🚀 Batch Solver</h2>
      <p>Solve multiple instances at once</p>
    </div>

    <div class="batch-form" v-if="!activeBatch">
      <!-- Domain Selection -->
      <div class="form-group">
        <label>Problem Domain</label>
        <select v-model="selectedDomain" class="select-input">
          <option value="">-- Select Domain --</option>
          <option value="tsp">TSP - Traveling Salesman</option>
          <option value="cvrp">CVRP - Vehicle Routing</option>
          <option value="cvrptw">CVRPTW - VRP with Time Windows</option>
          <option value="evrp">EVRP - Electric Vehicle Routing</option>
          <option value="co2vrp">CO2VRP - Green Routing</option>
          <option value="binpacking">Bin Packing</option>
          <option value="jobshop">Job Shop Scheduling</option>
          <option value="flowshop">Flow Shop Scheduling</option>
        </select>
      </div>

      <!-- Instance Pattern -->
      <div class="form-group">
        <label>Instance Pattern</label>
        <input
          v-model="instancePattern"
          type="text"
          placeholder="* (all instances)"
          class="text-input"
        />
        <small>Use * for all, or part of filename (e.g., "small", "100")</small>
      </div>

      <!-- Time Limit -->
      <div class="form-group">
        <label>Time Limit (seconds per instance)</label>
        <input
          v-model.number="timeLimit"
          type="number"
          min="10"
          max="3600"
          class="text-input"
        />
      </div>

      <!-- Advanced Parameters -->
      <div class="form-group">
        <label>
          <input type="checkbox" v-model="showAdvanced" />
          Show Advanced Parameters
        </label>
      </div>

      <div v-if="showAdvanced" class="advanced-params">
        <div class="param-row">
          <label>τ (tau)</label>
          <input v-model.number="parameters.tau" type="number" step="0.001" class="text-input" />
        </div>
        <div class="param-row">
          <label>d</label>
          <input v-model.number="parameters.d" type="number" step="0.1" class="text-input" />
        </div>
        <div class="param-row">
          <label>s1</label>
          <input v-model.number="parameters.s1" type="number" step="0.1" class="text-input" />
        </div>
        <div class="param-row">
          <label>s2</label>
          <input v-model.number="parameters.s2" type="number" class="text-input" />
        </div>
        <div class="param-row">
          <label>PS2HH</label>
          <input v-model.number="parameters.PS2HH" type="number" step="0.01" class="text-input" />
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="button-group">
        <button @click="startBatch" :disabled="!canStart" class="btn btn-primary">
          Start Batch Job
        </button>
        <button @click="viewHistory" class="btn btn-secondary">
          View History
        </button>
      </div>

      <!-- Error Message -->
      <div v-if="error" class="error-message">
        ⚠️ {{ error }}
      </div>
    </div>

    <!-- Active Batch Progress -->
    <div v-if="activeBatch" class="batch-progress">
      <BatchProgress
        :batchId="activeBatch.batch_id"
        @completed="onBatchCompleted"
        @view-results="viewResults"
      />
    </div>

    <!-- Results View -->
    <div v-if="showResults && selectedBatch" class="batch-results-view">
      <BatchResults
        :batchId="selectedBatch"
        @close="closeResults"
      />
    </div>

    <!-- History View -->
    <div v-if="showHistory" class="batch-history-view">
      <BatchHistory
        @close="closeHistory"
        @select-batch="viewBatchResults"
      />
    </div>
  </div>
</template>

<script>
import { ref, computed } from 'vue'
import { startBatchJob } from '../api/client'
import BatchProgress from './BatchProgress.vue'
import BatchResults from './BatchResults.vue'
import BatchHistory from './BatchHistory.vue'

export default {
  name: 'BatchSolver',
  components: {
    BatchProgress,
    BatchResults,
    BatchHistory
  },
  setup() {
    const selectedDomain = ref('')
    const instancePattern = ref('*')
    const timeLimit = ref(300)
    const showAdvanced = ref(false)
    const parameters = ref({
      tau: 0.015,
      d: 9.0,
      s1: 20.0,
      s2: 5,
      PS2HH: 0.3
    })

    const activeBatch = ref(null)
    const error = ref('')
    const showResults = ref(false)
    const showHistory = ref(false)
    const selectedBatch = ref(null)

    const canStart = computed(() => {
      return selectedDomain.value !== '' && timeLimit.value > 0
    })

    const startBatch = async () => {
      error.value = ''

      try {
        const response = await startBatchJob({
          domain: selectedDomain.value,
          instance_pattern: instancePattern.value,
          time_limit: timeLimit.value,
          parameters: showAdvanced.value ? parameters.value : {}
        })

        activeBatch.value = response
      } catch (e) {
        error.value = e.message || 'Failed to start batch job'
      }
    }

    const onBatchCompleted = () => {
      // Batch completed, show option to view results
      setTimeout(() => {
        if (confirm('Batch job completed! View results?')) {
          viewResults(activeBatch.value.batch_id)
        } else {
          activeBatch.value = null
        }
      }, 1000)
    }

    const viewResults = (batchId) => {
      selectedBatch.value = batchId
      showResults.value = true
      activeBatch.value = null
    }

    const closeResults = () => {
      showResults.value = false
      selectedBatch.value = null
    }

    const viewHistory = () => {
      showHistory.value = true
    }

    const closeHistory = () => {
      showHistory.value = false
    }

    const viewBatchResults = (batchId) => {
      closeHistory()
      viewResults(batchId)
    }

    return {
      selectedDomain,
      instancePattern,
      timeLimit,
      showAdvanced,
      parameters,
      activeBatch,
      error,
      canStart,
      showResults,
      showHistory,
      selectedBatch,
      startBatch,
      onBatchCompleted,
      viewResults,
      closeResults,
      viewHistory,
      closeHistory,
      viewBatchResults
    }
  }
}
</script>

<style scoped>
.batch-solver {
  max-width: 900px;
  margin: 0 auto;
  padding: 20px;
}

.header {
  text-align: center;
  margin-bottom: 30px;
}

.header h2 {
  margin: 0;
  font-size: 28px;
  color: #2c3e50;
}

.header p {
  margin: 5px 0 0 0;
  color: #7f8c8d;
}

.batch-form {
  background: white;
  border-radius: 8px;
  padding: 30px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.form-group {
  margin-bottom: 20px;
}

.form-group label {
  display: block;
  margin-bottom: 8px;
  font-weight: 600;
  color: #34495e;
}

.form-group small {
  display: block;
  margin-top: 5px;
  color: #95a5a6;
  font-size: 12px;
}

.select-input,
.text-input {
  width: 100%;
  padding: 10px;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 14px;
}

.select-input:focus,
.text-input:focus {
  outline: none;
  border-color: #3498db;
}

.advanced-params {
  background: #f8f9fa;
  padding: 15px;
  border-radius: 4px;
  margin-top: 10px;
}

.param-row {
  display: grid;
  grid-template-columns: 100px 1fr;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}

.param-row:last-child {
  margin-bottom: 0;
}

.button-group {
  display: flex;
  gap: 10px;
  margin-top: 25px;
}

.btn {
  padding: 12px 24px;
  border: none;
  border-radius: 4px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
}

.btn-primary {
  background: #3498db;
  color: white;
  flex: 1;
}

.btn-primary:hover:not(:disabled) {
  background: #2980b9;
}

.btn-primary:disabled {
  background: #bdc3c7;
  cursor: not-allowed;
}

.btn-secondary {
  background: #95a5a6;
  color: white;
}

.btn-secondary:hover {
  background: #7f8c8d;
}

.error-message {
  margin-top: 15px;
  padding: 12px;
  background: #ffe6e6;
  border-left: 4px solid #e74c3c;
  border-radius: 4px;
  color: #c0392b;
}

.batch-progress,
.batch-results-view,
.batch-history-view {
  margin-top: 20px;
}
</style>
