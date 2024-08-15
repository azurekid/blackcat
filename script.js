document.getElementById('functionAppForm').addEventListener('submit', function (event) {
	event.preventDefault();
	const ip = document.getElementById('ipAddress').value;
	const ipPattern = /^((25[0-4]|(2[0-4]|1\d|[1-9]|)\d)\.(25[0-5]|(2[0-4]|1\d|[1-9]|)\d\.))|^([0-9a-fA-F]{1,4}:){7}([0-9a-fA-F]{1,4})$/;
	const loadingDiv = document.getElementById('loading');
	const errorDiv = document.getElementById('error');
	const resultsDiv = document.getElementById('results');
	const noResultsDiv = document.getElementById('noResults');
	const wildcardDiv = document.getElementById('wildcard');

	// Hide error message
	errorDiv.style.display = 'none';
	noResultsDiv.style.display = 'none';
	wildcardDiv.style.display = 'none';
	
	if (!ipPattern.test(ip)) {
		errorDiv.textContent = 'Please enter a valid IP address.';
		errorDiv.style.display = 'block';
		return;
	}

	if (ip.includes('*')) {
		wildcardDiv.textContent = 'Wildcard detected, this might take longer';
		wildcardDiv.style.display = 'block';
		errorDiv.style.display = 'none';
	}

	// Show loading indicator after button is clicked
	loadingDiv.style.display = 'block';
	errorDiv.style.display = 'none';
	resultsDiv.innerHTML = ''; // Clear previous results
	
	
	const url = `https://blackcat.azurewebsites.net/api/ip?ip=${encodeURIComponent(ip)}`;
	
	fetch(url)
		.then(response => {
			if (!response.ok) {
				throw new Error(`HTTP error! status: ${response.status}`);
			}
			return response.json();
		})
		.then(data => {
			console.log('Response data:', data); // Log the response data

			// Hide loading indicator
			loadingDiv.style.display = 'none';
			wildcardDiv.style.display = 'none';

			// Check if data contains 'no results'
			if (data.includes('No matching service tag found for the given IP address.')) {
				noResultsDiv.style.display = 'block';
				return;
			}

			// Check if data is an array or a single object
			const results = Array.isArray(data) ? data : [data];

			// Create table
			const table = document.createElement('table');
			const thead = document.createElement('thead');
			const tbody = document.createElement('tbody');

			// Define table headers
			const headers = ['Region', 'Name', 'Prefix', 'Features'];
			const tr = document.createElement('tr');
			headers.forEach(header => {
				const th = document.createElement('th');
				th.textContent = header;
				tr.appendChild(th);
			});
			thead.appendChild(tr);
			table.appendChild(thead);

			// Populate table rows
			results.forEach(item => {
				const trBody = document.createElement('tr');
				trBody.appendChild(createCell(item.region));
				trBody.appendChild(createCell(item.systemService));
				// trBody.appendChild(createCell(item.platform));
				trBody.appendChild(createCell(item.addressPrefixes));
				trBody.appendChild(createCell(item.networkFeatures));
				tbody.appendChild(trBody);
			});
			table.appendChild(tbody);
			resultsDiv.appendChild(table);
		
        })
		.catch(error => {
            // Hide loading indicator in case of error
            loadingDiv.style.display = 'none';
            errorDiv.textContent = 'An error occurred while fetching data. Please try again later.';
            errorDiv.style.display = 'block';
        });
});

function createCell(text) {
	const td = document.createElement('td');
	td.textContent = text;
	return td;
}
