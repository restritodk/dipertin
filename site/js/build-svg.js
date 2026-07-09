const fs = require('fs');
const path = require('path');

// Read the SVG source file
const sourcePath = path.join(__dirname, '..', '..', '..', '..', 'Users', 'euric', '.cursor', 'projects', 'c-Projeto-DiPertin', 'agent-tools', 'b1a8743f-0ac2-4741-ab7c-c4fbfb7e3996.txt');
const source = fs.readFileSync(sourcePath, 'utf-8');

// Extract all path elements with their d attributes
// The source has format: <path stroke="#FFFFFF" stroke-width="1.0404" ... d="M...c...z"></path>
const pathRegex = /<path\s+[^>]*d="([^"]+)"[^>]*><\/path>/g;
const paths = [];
let match;

while ((match = pathRegex.exec(source)) !== null) {
  const d = match[1];
  // Check if this is a state path or a circle path
  const fullTag = match[0];
  if (fullTag.includes('class="circle"')) continue; // skip circle paths
  paths.push(d);
}

// Determine which path corresponds to which state by looking at the title elements
// The source has: <a xlink:href="#matogrosso"><title>Mato Grosso</title><path .../></a>
const stateRegex = /<a xlink:href="#([^"]+)"[^>]*>[\s\S]*?<title>([^<]+)<\/title>[\s\S]*?<path\s+[^>]*d="([^"]+)"[^>]*><\/path>/g;

const MTPath = /<a xlink:href="#matogrosso"[\s\S]*?<title>Mato Grosso<\/title>[\s\S]*?<path\s+[^>]*d="([^"]+)"[^>]*><\/path>/.exec(source);

console.log('MT path:', MTPath ? MTPath[1].substring(0, 50) : 'NOT FOUND');

// Build the output SVG paths
let result = '';

// Assign colors to states - MT gets #5B0DBA, others get #ECE7F7
for (const d of paths) {
  const isMT = d.includes('142.237,173.962') || d.includes('200.0244');
  result += `              <path d="${d}" fill="${isMT ? '#5B0DBA' : '#ECE7F7'}" stroke="rgba(91,13,186,0.12)" stroke-width="1.5"${isMT ? ' opacity="0.95"' : ''}/>\n`;
  if (isMT) {
    result += `              <path d="${d}" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="3"/>\n`;
  }
}

fs.writeFileSync(path.join(__dirname, 'svg-output.txt'), result);
console.log('Generated SVG state paths. Total states:', paths.length);
