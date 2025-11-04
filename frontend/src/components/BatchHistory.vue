<template>
  <div class="batch-history">
    <div class="history-header">
      <h3>📚 Batch History</h3>
      <button @click="$emit('close')" class="btn btn-close">✕ Close</button>
    </div>

    <div v-if="jobs" class="history-content">
      <div v-if="jobs.length === 0" class="empty-state">
        <p>📭 No batch jobs yet</p>
        <small>Start a batch job to see it here</small>
      </div>

      <div v-else class="jobs-list">
        <div
          v-for="job in jobs"
          :key="job.batch_id"
          class="job-card"
          :class="job.status"
          @click="selectJob(job.batch_id)"
        >
          <div class="job-header">
            <div class="job-domain">{{ job.domain.toUpperCase() }}</div>
            <div class="job-status" :class="job.status">
              {{ job.status }}
            </div>
          </div>

          <div class="job-stats">
            <div class="stat">
              <span class="stat-label">Total:</span>
              <span class="stat-value">{{ job.total_instances }}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Completed:</span>
              <span class="stat-value">{{ job.completed_instances }}</span>
            </div>
            <div class="stat">
              <span class="stat-label">Started:</span>
              <span class="stat-value">{{ formatDate(job.started_at) }}</span>
            </div>
          </div>

          <div class="job-footer">
            <span class="job-id">{{ job.batch_id.substring(0, 12) }}...</span>
            <span class="job-action">Click to view →</span>
          </div>
        </div>
      </div>

      <button v-if="jobs.length > 0" @click="clearHistory" class="btn btn-clear">
        🗑️ Clear All History
      </button>
    </div>

    <div v-else class="loading">
      <div class="spinner"></div>
      <p>Loading history...</p>
    </div>
  </div>
</template>

<script>
import { ref, onMounted } from 'vue'
import { getBatchList } from '../api/client'

export default {
  name: 'BatchHistory',
  emits: ['close', 'select-batch'],
  setup(props, { emit }) {
    const jobs = ref(null)

    const formatDate = (timestamp) => {
      const date = new Date(timestamp * 1000)
      return date.toLocaleString()
    }

    const selectJob = (batchId) => {
      emit('select-batch', batchId)
    }

    const clearHistory = () => {
      if (confirm('Clear all batch history? This cannot be undone.')) {
        // In a real app, you would call an API to clear history
        jobs.value = []
      }
    }

    onMounted(async () => {
      try {
        const response = await getBatchList()
        jobs.value = response.jobs
      } catch (e) {
        console.error('Failed to load history:', e)
        jobs.value = []
      }
    })

    return {
      jobs,
      formatDate,
      selectJob,
      clearHistory
    }
  }
}
</script>

<style scoped>
.batch-history {
  background: white;
  border-radius: 8px;
  padding: 30px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.1);
  max-height: 90vh;
  overflow-y: auto;
}

.history-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 25px;
  padding-bottom: 15px;
  border-bottom: 2px solid #ecf0f1;
}

.history-header h3 {
  margin: 0;
  font-size: 22px;
  color: #2c3e50;
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

.btn-close {
  background: #95a5a6;
  color: white;
}

.btn-close:hover {
  background: #7f8c8d;
}

.btn-clear {
  width: 100%;
  margin-top: 20px;
  background: #e74c3c;
  color: white;
}

.btn-clear:hover {
  background: #c0392b;
}

.empty-state {
  text-align: center;
  padding: 60px 20px;
  color: #95a5a6;
}

.empty-state p {
  font-size: 18px;
  margin: 0 0 10px 0;
}

.empty-state small {
  font-size: 13px;
}

.jobs-list {
  display: grid;
  gap: 15px;
}

.job-card {
  background: #f8f9fa;
  border: 2px solid #ecf0f1;
  border-radius: 8px;
  padding: 20px;
  cursor: pointer;
  transition: all 0.3s;
}

.job-card:hover {
  border-color: #3498db;
  box-shadow: 0 4px 12px rgba(52, 152, 219, 0.2);
  transform: translateY(-2px);
}

.job-card.completed {
  border-left: 4px solid #2ecc71;
}

.job-card.running {
  border-left: 4px solid #3498db;
  animation: pulse 2s infinite;
}

.job-card.error {
  border-left: 4px solid #e74c3c;
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.8; }
}

.job-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 15px;
}

.job-domain {
  font-size: 16px;
  font-weight: 700;
  color: #2c3e50;
}

.job-status {
  padding: 4px 12px;
  border-radius: 12px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
}

.job-status.completed {
  background: #2ecc71;
  color: white;
}

.job-status.running {
  background: #3498db;
  color: white;
}

.job-status.error {
  background: #e74c3c;
  color: white;
}

.job-stats {
  display: flex;
  gap: 20px;
  margin-bottom: 15px;
}

.stat {
  display: flex;
  gap: 5px;
  font-size: 13px;
}

.stat-label {
  color: #7f8c8d;
}

.stat-value {
  font-weight: 600;
  color: #34495e;
}

.job-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-top: 15px;
  border-top: 1px solid #ecf0f1;
  font-size: 12px;
}

.job-id {
  font-family: monospace;
  color: #95a5a6;
}

.job-action {
  color: #3498db;
  font-weight: 600;
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
