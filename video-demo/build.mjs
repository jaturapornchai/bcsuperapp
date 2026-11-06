// clips/*/{index,cursor}.json + boxes.json + facts.json -> data.js (consumed by video.html)
import fs from "node:fs";
const rd = f => JSON.parse(fs.readFileSync(f, "utf8")), scenes = {};
for (const id of fs.readdirSync("clips")) {
  if (!fs.existsSync(`clips/${id}/index.json`)) continue;
  scenes[id] = { index: rd(`clips/${id}/index.json`), cursor: fs.existsSync(`clips/${id}/cursor.json`) ? rd(`clips/${id}/cursor.json`) : [] };
}
fs.writeFileSync("data.js", "window.DATA = " + JSON.stringify({ boxes: fs.existsSync("boxes.json") ? rd("boxes.json") : {}, facts: fs.existsSync("facts.json") ? rd("facts.json") : { sims: {} }, scenes }) + ";");
console.log(Object.keys(scenes).join(","), Object.keys(rd("boxes.json")).join(","));
