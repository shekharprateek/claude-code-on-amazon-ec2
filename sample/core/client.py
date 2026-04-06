"""
HTTP client for external API calls.
"""

import httpx

BASE_URL = "https://api.example.com"


def fetch_data(endpoint: str) -> dict:
    """Fetch data from the external API synchronously.

    Args:
        endpoint: API endpoint path (e.g., 'users/123')

    Returns:
        Parsed JSON response as a dict
    """
    with httpx.Client() as client:
        response = client.get(f"{BASE_URL}/{endpoint}")
        response.raise_for_status()
        return response.json()


async def fetch_data_async(endpoint: str) -> dict:
    """Fetch data from the external API asynchronously.

    Args:
        endpoint: API endpoint path

    Returns:
        Parsed JSON response as a dict
    """
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BASE_URL}/{endpoint}")
        response.raise_for_status()
        return response.json()
