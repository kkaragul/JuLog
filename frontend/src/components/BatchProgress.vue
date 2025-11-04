<template>
  <div class="batch-progress">
    <div class="progress-header">
      <h3>Batch Job Progress</h3>
      <span class="batch-id">ID: {{ batchId.substring(0, 8) }}...</span>
    </div>

    <div v-if="status" class="progress-content">
      <!-- Overall Progress Bar -->
      <div class="progress-bar-container">
        <div class="progress-info">
          <span class="progress-label">{{ progressText }}</span>
          <span class="progress-percent">{{ progressPercent }}%</span>
        </div>
        <div class="progress-bar">
          <div
            class="progress-fill"
            :style="{ width: progressPercent + '%' }"
            :class="statusClass"
          ></div>
        </div>
      </div>

      <!-- Statistics -->
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-value">{{ status.total_instances }}</div>
          <div class="stat-label">Total Instances</div>
        </div>
        <div class="stat-card success">
          <div class="stat-value">{{ status.completed_instances }}</div>
          <div class="stat-label">Completed</div>
        </div>
        <div class="stat-card error">
          <div class="stat-value">{{ status.failed_instances }}</div>
          <div class="stat-label">Failed</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">{{ elapsedTime }}s</div>
          <div class="stat-label">Elapsed</div>
        </div>
      </div>

      <!-- Current Instance -->
      <div v-if="status.current_instance" class="current-instance">
        <div class="spinner"></div>
        <div>
          <strong>Currently solving:</strong>
          <span class="instance-name">{{ status.current_instance }}</span>
          <span class="instance-index">({{ status.current_index || 0 }}/{{ status.total_instances }})</span>
        </div>
      </div>

      <!-- Recent Results -->
      <div v-if="status.results && status.results.length > 0" class="recent-results">
        <h4>Recent Results</h4>
        <div class="results-list">
          <div
            v-for="(result, index) in recentResults"
            :key="index"
            class="result-item"
            :class="result.status"
          >
            <span class="result-icon">
              {{ result.status === 'completed' ? '✓' : '✗' }}
            </span>
            <span class="result-name">{{ result.instance_name }}</span>
            <span v-if="result.status === 'completed'" class="result-improvement">
              {{ result.improvement_pct?.toFixed(2) }}% improvement
            </span>
            <span v-else class="result-error">{{ result.error }}</span>
          </div>
        </div>
      </div>

      <!-- Action Buttons -->
      <div class="action-buttons">
        <button
          v-if="status.status === 'completed'"
          @click="$emit('view-results', batchId)"
          class="btn btn-primary"
        >
          📊 View Full Results
        </button>
        <button
          v-if="status.status === 'running'"
          class="btn btn-secondary"
          disabled
        >
          ⏳ Solving...
        </button>
      </div>
    </div>

    <div v-else class="loading">
      <div class="spinner"></div>
      <p>Loading batch status...</p>
    </div>
  </div>
</template>

<script>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { getBatchStatus } from '../api/client'

export default {
  name: 'BatchProgress',
  props: {
    batchId: {
      type: String,
      required: true
    }
  },
  emits: ['completed', 'view-results'],
  setup(props, { emit }) {
    const status = ref(null)
    const startTime = ref(Date.now())
    const currentTime = ref(Date.now())
    let pollInterval = null
    let timeInterval = null

    const progressPercent = computed(() => {
      if (!status.value) return 0
      return Math.round((status.value.completed_instances / status.value.total_instances) * 100)
    })

    const progressText = computed(() => {
      if (!status.value) return ''
      return `${status.value.completed_instances} / ${status.value.total_instances} completed`
    })

    const statusClass = computed(() => {
      if (!status.value) return ''
      return status.value.status === 'completed' ? 'completed' :
             status.value.status === 'error' ? 'error' : 'running'
    })

    const elapsedTime = computed(() => {
      return Math.floor((currentTime.value - startTime.value) / 1000)
    })

    const recentResults = computed(() => {
      if (!status.value || !status.value.results) return []
      return status.value.results.slice(-5).reverse()
    })

    const fetchStatus = async () => {
      try {
        const response = await getBatchStatus(props.batchId)
        status.value = response

        // Check if completed
        if (response.status === 'completed' && pollInterval) {
          clearInterval(pollInterval)
          pollInterval = null
          emit('completed')
        }
      } catch (e) {
        console.error('Failed to fetch batch status:', e)
      }
    }

    onMounted(() => {
      // Initial fetch
      fetchStatus()

      // Poll every 2 seconds
      pollInterval = setInterval(fetchStatus, 2000)

      // Update elapsed time every second
      timeInterval = setInterval(() => {
        currentTime.value = Date.now()
      }, 1000)
    })

    onUnmounted(() => {
      if (pollInterval) clearInterval(pollInterval)
      if (timeInterval) clearInterval(timeInterval)
    })

    return {
      status,
      progressPercent,
      progressText,
      statusClass,
      elapsedTime,
      recentResults
    }
  }
}
</script>

<style scoped>
.batch-progress {
  background: white;
  border-radius: 8px;
  padding: 30px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
}

.progress-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 25px;
  padding-bottom: 15px;
  border-bottom: 2px solid #ecf0f1;
}

.progress-header h3 {
  margin: 0;
  font-size: 20px;
  color: #2c3e50;
}

.batch-id {
  font-family: monospace;
  font-size: 12px;
  color: #95a5a6;
  background: #f8f9fa;
  padding: 4px 8px;
  border-radius: 4px;
}

.progress-bar-container {
  margin-bottom: 25px;
}

.progress-info {
  display: flex;
  justify-content: space-between;
  margin-bottom: 8px;
  font-size: 14px;
}

.progress-label {
  color: #34495e;
  font-weight: 600;
}

.progress-percent {
  color: #3498db;
  font-weight: 700;
}

.progress-bar {
  height: 24px;
  background: #ecf0f1;
  border-radius: 12px;
  overflow: hidden;
  position: relative;
}

.progress-fill {
  height: 100%;
  transition: width 0.5s ease, background 0.3s;
  border-radius: 12px;
}

.progress-fill.running {
  background: linear-gradient(90deg, #3498db, #5dade2);
  animation: pulse 2s infinite;
}

.progress-fill.completed {
  background: linear-gradient(90deg, #2ecc71, #58d68d);
}

.progress-fill.error {
  background: linear-gradient(90deg, #e74c3c, #ec7063);
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.8; }
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 15px;
  margin-bottom: 25px;
}

.stat-card {
  background: #f8f9fa;
  padding: 20px;
  border-radius: 8px;
  text-align: center;
  border: 2px solid #ecf0f1;
}

.stat-card.success {
  background: #e8f8f5;
  border-color: #2ecc71;
}

.stat-card.error {
  background: #fdedec;
  border-color: #e74c3c;
}

.stat-value {
  font-size: 32px;
  font-weight: 700;
  color: #2c3e50;
  margin-bottom: 5px;
}

.stat-label {
  font-size: 12px;
  color: #7f8c8d;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.current-instance {
  display: flex;
  align-items: center;
  gap: 15px;
  padding: 15px;
  background: #e3f2fd;
  border-left: 4px solid #2196f3;
  border-radius: 4px;
  margin-bottom: 25px;
}

.spinner {
  width: 20px;
  height: 20px;
  border: 3px solid #e3f2fd;
  border-top-color: #2196f3;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.instance-name {
  font-weight: 600;
  color: #1976d2;
  margin-left: 8px;
}

.instance-index {
  margin-left: 8px;
  color: #7f8c8d;
  font-size: 13px;
}

.recent-results {
  margin-bottom: 25px;
}

.recent-results h4 {
  margin: 0 0 15px 0;
  font-size: 16px;
  color: #34495e;
}

.results-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.result-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px;
  background: #f8f9fa;
  border-radius: 4px;
  font-size: 13px;
}

.result-item.completed {
  border-left: 3px solid #2ecc71;
}

.result-item.failed {
  border-left: 3px solid #e74c3c;
}

.result-icon {
  font-size: 16px;
  font-weight: 700;
}

.result-item.completed .result-icon {
  color: #2ecc71;
}

.result-item.failed .result-icon {
  color: #e74c3c;
}

.result-name {
  flex: 1;
  font-weight: 600;
  color: #34495e;
}

.result-improvement {
  color: #27ae60;
  font-weight: 600;
}

.result-error {
  color: #e74c3c;
  font-size: 11px;
}

.action-buttons {
  display: flex;
  gap: 10px;
}

.btn {
  flex: 1;
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
}

.btn-primary:hover {
  background: #2980b9;
}

.btn-secondary {
  background: #95a5a6;
  color: white;
  cursor: not-allowed;
}

.loading {
  text-align: center;
  padding: 40px;
  color: #7f8c8d;
}

.loading .spinner {
  width: 40px;
  height: 40px;
  margin: 0 auto 20px;
  border-width: 4px;
}
</style>
