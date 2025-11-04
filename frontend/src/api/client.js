/**
 * MSHH Solver API Client
 *
 * Axios-based client for communicating with MSHH backend API.
 */

import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

/**
 * Health check
 */
export async function checkHealth() {
  const response = await api.get('/api/health');
  return response.data;
}

/**
 * List available instances
 */
export async function listInstances() {
  const response = await api.get('/api/instances/list');
  return response.data;
}

/**
 * Solve TSP instance
 * @param {string} instanceFile - Path to instance file
 * @param {number} timeLimit - Time limit in seconds
 * @param {object} parameters - MSHH parameters
 */
export async function solveTSP(instanceFile, timeLimit = 60, parameters = {}) {
  const response = await api.post('/api/solve/tsp', {
    instance_file: instanceFile,
    time_limit: timeLimit,
    parameters,
  });
  return response.data;
}

/**
 * Solve CVRP instance
 * @param {string} instanceFile - Path to instance file
 * @param {number} timeLimit - Time limit in seconds
 * @param {object} parameters - MSHH parameters
 */
export async function solveCVRP(instanceFile, timeLimit = 60, parameters = {}) {
  const response = await api.post('/api/solve/cvrp', {
    instance_file: instanceFile,
    time_limit: timeLimit,
    parameters,
  });
  return response.data;
}

/**
 * Get job status
 * @param {string} jobId - Job ID
 */
export async function getJobStatus(jobId) {
  const response = await api.get(`/api/status/${jobId}`);
  return response.data;
}

/**
 * Upload instance file
 * @param {File} file - File to upload
 * @param {string} domain - Domain type ('tsp' or 'cvrp')
 */
export async function uploadInstance(file, domain) {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('domain', domain);

  const response = await api.post('/api/upload/instance', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  });
  return response.data;
}

/**
 * Poll job status until completion
 * @param {string} jobId - Job ID
 * @param {function} onProgress - Progress callback
 * @param {number} interval - Polling interval in ms
 */
export async function pollJobStatus(jobId, onProgress, interval = 1000) {
  return new Promise((resolve, reject) => {
    const poll = async () => {
      try {
        const status = await getJobStatus(jobId);

        if (onProgress) {
          onProgress(status);
        }

        if (status.status === 'completed') {
          resolve(status.result);
        } else if (status.status === 'error') {
          reject(new Error(status.error || 'Job failed'));
        } else {
          // Continue polling
          setTimeout(poll, interval);
        }
      } catch (error) {
        reject(error);
      }
    };

    poll();
  });
}

/**
 * BATCH SOLVING APIs
 */

/**
 * Start a batch solving job
 * @param {object} config - Batch configuration
 */
export async function startBatchJob(config) {
  const response = await api.post('/api/batch/start', config);
  return response.data;
}

/**
 * Get batch job status
 * @param {string} batchId - Batch ID
 */
export async function getBatchStatus(batchId) {
  const response = await api.get(`/api/batch/status/${batchId}`);
  return response.data;
}

/**
 * List all batch jobs
 */
export async function getBatchList() {
  const response = await api.get('/api/batch/list');
  return response.data;
}

/**
 * Get detailed batch results
 * @param {string} batchId - Batch ID
 */
export async function getBatchResults(batchId) {
  const response = await api.get(`/api/batch/results/${batchId}`);
  return response.data;
}

/**
 * Download batch results as CSV
 * @param {string} batchId - Batch ID
 */
export async function downloadBatchCSV(batchId) {
  const response = await api.get(`/api/batch/download/${batchId}`, {
    responseType: 'blob'
  });

  // Create download link
  const url = window.URL.createObjectURL(new Blob([response.data]));
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', `batch_results_${batchId}.csv`);
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
}

/**
 * Delete a batch job
 * @param {string} batchId - Batch ID
 */
export async function deleteBatchJob(batchId) {
  const response = await api.delete(`/api/batch/delete/${batchId}`);
  return response.data;
}

export default api;
