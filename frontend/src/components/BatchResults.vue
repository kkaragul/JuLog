<template>
  <div class="batch-results">
    <div class="results-header">
      <div>
        <h3>📊 Batch Results</h3>
        <span class="batch-info">{{ domain.toUpperCase() }} - {{ summary.completed }} instances</span>
      </div>
      <div class="header-actions">
        <button @click="downloadCSV" class="btn btn-download">📥 Download CSV</button>
        <button @click="$emit('close')" class="btn btn-close">✕</button>
      </div>
    </div>

    <div v-if="results" class="results-content">
      <!-- Summary Cards -->
      <div class="summary-grid">
        <div class="summary-card success">
          <div class="card-icon">✓</div>
          <div class="card-content">
            <div class="card-value">{{ summary.completed }}</div>
            <div class="card-label">Completed</div>
          </div>
        </div>
        <div class="summary-card error">
          <div class="card-icon">✗</div>
          <div class="card-content">
            <div class="card-value">{{ summary.failed }}</div>
            <div class="card-label">Failed</div>
          </div>
        </div>
        <div class="summary-card">
          <div class="card-icon">📈</div>
          <div class="card-content">
            <div class="card-value">{{ summary.avg_improvement }}%</div>
            <div class="card-label">Avg Improvement</div>
          </div>
        </div>
        <div class="summary-card">
          <div class="card-icon">⏱️</div>
          <div class="card-content">
            <div class="card-value">{{ summary.avg_time }}s</div>
            <div class="card-label">Avg Time</div>
          </div>
        </div>
      </div>

      <!-- Visualization Charts -->
      <div class="charts-section">
        <div class="chart-card">
          <h4>Improvement by Instance</h4>
          <div class="bar-chart">
            <div
              v-for="(result, index) in completedResults"
              :key="index"
              class="bar-item"
            >
              <div class="bar-label">{{ truncateName(result.instance_name) }}</div>
              <div class="bar-container">
                <div
                  class="bar-fill"
                  :style="{ width: getBarWidth(result.improvement_pct) + '%' }"
                >
                  <span class="bar-value">{{ result.improvement_pct.toFixed(1) }}%</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="chart-card">
          <h4>Computation Time</h4>
          <div class="bar-chart">
            <div
              v-for="(result, index) in completedResults"
              :key="index"
              class="bar-item"
            >
              <div class="bar-label">{{ truncateName(result.instance_name) }}</div>
              <div class="bar-container">
                <div
                  class="bar-fill time-bar"
                  :style="{ width: getTimeBarWidth(result.computation_time) + '%' }"
                >
                  <span class="bar-value">{{ result.computation_time.toFixed(1) }}s</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Detailed Results Table -->
      <div class="table-section">
        <h4>Detailed Results</h4>
        <div class="table-container">
          <table class="results-table">
            <thead>
              <tr>
                <th>Instance</th>
                <th>Status</th>
                <th>Initial</th>
                <th>Best</th>
                <th>Improvement</th>
                <th>Improvement %</th>
                <th>Time (s)</th>
                <th>Stages</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(result, index) in results.results"
                :key="index"
                :class="result.status"
              >
                <td class="instance-cell">{{ result.instance_name }}</td>
                <td>
                  <span class="status-badge" :class="result.status">
                    {{ result.status }}
                  </span>
                </td>
                <template v-if="result.status === 'completed'">
                  <td class="number-cell">{{ result.initial_objective.toFixed(2) }}</td>
                  <td class="number-cell">{{ result.best_objective.toFixed(2) }}</td>
                  <td class="number-cell">{{ result.improvement.toFixed(2) }}</td>
                  <td class="improvement-cell">{{ result.improvement_pct.toFixed(2) }}%</td>
                  <td class="number-cell">{{ result.computation_time.toFixed(2) }}</td>
                  <td class="number-cell">{{ result.stages_executed }}</td>
                </template>
                <template v-else>
                  <td colspan="6" class="error-cell">{{ result.error || 'Failed' }}</td>
                </template>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <div v-else class="loading">
      <div class="spinner"></div>
      <p>Loading results...</p>
    </div>
  </div>
</template>

<script>
import { ref, computed, onMounted } from 'vue'
import { getBatchResults, downloadBatchCSV } from '../api/client'

export default {
  name: 'BatchResults',
  props: {
    batchId: {
      type: String,
      required: true
    }
  },
  emits: ['close'],
  setup(props) {
    const results = ref(null)

    const domain = computed(() => results.value?.domain || '')
    const summary = computed(() => results.value?.summary || {})

    const completedResults = computed(() => {
      if (!results.value) return []
      return results.value.results.filter(r => r.status === 'completed')
    })

    const getBarWidth = (improvement) => {
      if (!summary.value.best_improvement) return 0
      return (improvement / summary.value.best_improvement) * 100
    }

    const getTimeBarWidth = (time) => {
      if (!completedResults.value.length) return 0
      const maxTime = Math.max(...completedResults.value.map(r => r.computation_time))
      return (time / maxTime) * 100
    }

    const truncateName = (name) => {
      if (name.length > 20) return name.substring(0, 17) + '...'
      return name
    }

    const downloadCSV = async () => {
      try {
        await downloadBatchCSV(props.batchId)
      } catch (e) {
        alert('Failed to download CSV: ' + e.message)
      }
    }

    onMounted(async () => {
      try {
        results.value = await getBatchResults(props.batchId)
      } catch (e) {
        console.error('Failed to load results:', e)
      }
    })

    return {
      results,
      domain,
      summary,
      completedResults,
      getBarWidth,
      getTimeBarWidth,
      truncateName,
      downloadCSV
    }
  }
}
</script>

<style scoped>
.batch-results {
  background: white;
  border-radius: 8px;
  padding: 30px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  max-height: 90vh;
  overflow-y: auto;
}

.results-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 25px;
  padding-bottom: 15px;
  border-bottom: 2px solid #ecf0f1;
}

.results-header h3 {
  margin: 0 0 5px 0;
  font-size: 22px;
  color: #2c3e50;
}

.batch-info {
  font-size: 13px;
  color: #7f8c8d;
}

.header-actions {
  display: flex;
  gap: 10px;
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
}

.btn-download {
  background: #27ae60;
  color: white;
}

.btn-download:hover {
  background: #229954;
}

.btn-close {
  background: #95a5a6;
  color: white;
}

.btn-close:hover {
  background: #7f8c8d;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 15px;
  margin-bottom: 30px;
}

.summary-card {
  display: flex;
  align-items: center;
  gap: 15px;
  background: #f8f9fa;
  padding: 20px;
  border-radius: 8px;
  border: 2px solid #ecf0f1;
}

.summary-card.success {
  background: #e8f8f5;
  border-color: #2ecc71;
}

.summary-card.error {
  background: #fdedec;
  border-color: #e74c3c;
}

.card-icon {
  font-size: 32px;
}

.card-value {
  font-size: 28px;
  font-weight: 700;
  color: #2c3e50;
  line-height: 1;
  margin-bottom: 5px;
}

.card-label {
  font-size: 12px;
  color: #7f8c8d;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.charts-section {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
  gap: 20px;
  margin-bottom: 30px;
}

.chart-card {
  background: #f8f9fa;
  padding: 20px;
  border-radius: 8px;
}

.chart-card h4 {
  margin: 0 0 15px 0;
  font-size: 14px;
  color: #34495e;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.bar-chart {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.bar-item {
  display: flex;
  align-items: center;
  gap: 10px;
}

.bar-label {
  width: 120px;
  font-size: 12px;
  color: #34495e;
  text-align: right;
  flex-shrink: 0;
}

.bar-container {
  flex: 1;
  height: 24px;
  background: #ecf0f1;
  border-radius: 4px;
  position: relative;
  overflow: hidden;
}

.bar-fill {
  height: 100%;
  background: linear-gradient(90deg, #3498db, #5dade2);
  border-radius: 4px;
  display: flex;
  align-items: center;
  padding: 0 8px;
  min-width: 50px;
  transition: width 0.5s ease;
}

.bar-fill.time-bar {
  background: linear-gradient(90deg, #9b59b6, #bb8fce);
}

.bar-value {
  font-size: 11px;
  font-weight: 600;
  color: white;
}

.table-section {
  margin-bottom: 20px;
}

.table-section h4 {
  margin: 0 0 15px 0;
  font-size: 16px;
  color: #34495e;
}

.table-container {
  overflow-x: auto;
}

.results-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.results-table thead {
  background: #34495e;
  color: white;
}

.results-table th {
  padding: 12px;
  text-align: left;
  font-weight: 600;
  text-transform: uppercase;
  font-size: 11px;
  letter-spacing: 0.5px;
}

.results-table tbody tr {
  border-bottom: 1px solid #ecf0f1;
}

.results-table tbody tr:hover {
  background: #f8f9fa;
}

.results-table td {
  padding: 12px;
}

.instance-cell {
  font-weight: 600;
  color: #2c3e50;
}

.number-cell {
  text-align: right;
  font-family: monospace;
}

.improvement-cell {
  text-align: right;
  font-weight: 600;
  color: #27ae60;
}

.error-cell {
  color: #e74c3c;
  font-style: italic;
}

.status-badge {
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
}

.status-badge.completed {
  background: #2ecc71;
  color: white;
}

.status-badge.failed {
  background: #e74c3c;
  color: white;
}

.loading {
  text-align: center;
  padding: 60px 20px;
  color: #7f8c8d;
}

.spinner {
  width: 40px;
  height: 40px;
  border: 4px solid #ecf0f1;
  border-top-color: #3498db;
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin: 0 auto 20px;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
