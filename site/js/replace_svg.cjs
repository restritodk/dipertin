const fs = require('fs');

// Read the HTML file
const htmlPath = 'C:\\Projeto\\DiPertin\\site\\index.html';
let html = fs.readFileSync(htmlPath, 'utf-8');

// Read the new SVG content
const svgPath = 'C:\\Projeto\\DiPertin\\site\\js\\svg_output.txt';
const newSvg = fs.readFileSync(svgPath, 'utf-8');

// The old SVG - from the start tag to the end tag
const oldSvgStart = '          <div class="onde-atuamos__mapa-wrapper">\n            <svg class="onde-atuamos__mapa" viewBox="0 0 400 440" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Mapa do Brasil com destaque para Mato Grosso">';
const oldSvgEnd = '            </svg>\n          </div>';

// Find the section to replace
const startIdx = html.indexOf(oldSvgStart);
const endIdx = html.indexOf(oldSvgEnd, startIdx) + oldSvgEnd.length;

if (startIdx === -1 || endIdx === -1) {
  console.error('Could not find old SVG in HTML');
  process.exit(1);
}

const before = html.substring(0, startIdx);
const after = html.substring(endIdx);

// Build the new HTML section
const newSection = `          <div class="onde-atuamos__mapa-wrapper">
${newSvg}
          </div>`;

html = before + newSection + after;

fs.writeFileSync(htmlPath, html, 'utf-8');
console.log('SVG replacement completed successfully!');
console.log('Old SVG removed, new SVG with', (newSvg.match(/<path/g) || []).length, 'paths inserted.');
