const mapping = require('./display_location_mapping.json');
const neighborhoodTokens = require('./display_location_tokens.json');

function normalizeLabel(value) {
  if (!value) return null;
  const trimmed = String(value).trim();
  if (!trimmed) return null;
  return trimmed.replace(/\s+/g, ' ');
}

function extractZip(address) {
  if (!address) return null;
  const match = String(address).match(/(\d{5})(?:[-\s]\d{4})?$/);
  return match ? match[1] : null;
}

function boroughFromZip(zip) {
  if (!zip) return null;
  if (/^112/.test(zip)) return 'Brooklyn';
  if (/^(111|113|114|116)/.test(zip)) return 'Queens';
  if (/^104/.test(zip)) return 'Bronx';
  if (/^103/.test(zip)) return 'Staten Island';
  if (/^(100|101|102)/.test(zip)) return 'Manhattan';
  if (/^(110|115)/.test(zip)) return 'Nassau';
  if (/^(117|118|119)/.test(zip)) return 'Suffolk';
  return null;
}

function boroughFromAddress(lowerAddress) {
  if (!lowerAddress) return null;
  if (lowerAddress.includes(' brooklyn')) return 'Brooklyn';
  if (lowerAddress.includes(' queens')) return 'Queens';
  if (lowerAddress.includes(' bronx')) return 'Bronx';
  if (lowerAddress.includes(' staten island')) return 'Staten Island';
  if (lowerAddress.includes(' new york')) return 'Manhattan';
  return null;
}

function cityFromAddress(address) {
  if (!address) return null;
  const match = address.match(/,\s*([^,]+?),\s*(?:NY|New York)\b/i);
  if (match) return titleCase(match[1]);
  const parts = address.split(',').map((part) => part.trim()).filter(Boolean);
  if (parts.length >= 2) {
    const candidate = parts[parts.length - 2];
    if (candidate && !/\d{5}$/.test(candidate)) {
      return titleCase(candidate);
    }
  }
  return null;
}

function titleCase(value) {
  if (!value) return null;
  const lower = value.toLowerCase();
  return lower.replace(/(^|[\s-/])([a-z])/g, (_, prefix, char) => `${prefix}${char.toUpperCase()}`);
}

function detectNeighborhood(lowerAddress, zip) {
  if (zip && mapping[zip] && mapping[zip].locality) {
    return mapping[zip].locality;
  }
  for (const entry of neighborhoodTokens) {
    if (lowerAddress.includes(entry.token)) {
      return entry.label;
    }
  }
  return null;
}

function detectRegion(zip, lowerAddress) {
  const fromZip = boroughFromZip(zip);
  if (fromZip) return fromZip;
  return boroughFromAddress(lowerAddress);
}

function resolveDisplayLocation(input) {
  if (!input) return null;
  const provided = normalizeLabel(input.displayLocation || input.display_location);
  if (provided) return provided;

  const address = input.address ? String(input.address).trim() : '';
  if (!address) return null;

  const lower = address.toLowerCase();
  const zip = extractZip(address);
  const fromMap = zip && mapping[zip] ? mapping[zip] : null;

  let region = (fromMap && fromMap.region) || detectRegion(zip, lower);
  let locality = fromMap && fromMap.locality ? fromMap.locality : detectNeighborhood(lower, zip);

  if ((!locality || (region && locality.toLowerCase() === region.toLowerCase())) &&
      (region === 'Nassau' || region === 'Suffolk')) {
    locality = cityFromAddress(address);
  }

  if ((!locality || !region) && !fromMap) {
    const fromCity = cityFromAddress(address);
    if (fromCity && (!region || fromCity.toLowerCase() !== region.toLowerCase())) {
      locality = locality || fromCity;
    }
  }

  if (locality && region && locality.toLowerCase() !== region.toLowerCase()) {
    return normalizeLabel(`${locality}, ${region}`);
  }
  if (region) return normalizeLabel(region);
  if (locality) return normalizeLabel(locality);
  return null;
}

module.exports = {
  resolveDisplayLocation,
  extractZip,
  boroughFromZip,
  normalizeLabel,
};
