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

export default api;
