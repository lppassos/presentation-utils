import GanttPlugin from "/plugins/marp/gantt-diagram/index.js";
import CustomDiagramPlugin from "/plugins/marp/custom-diagram/index.js";
import hljs from "markdown-it-highlightjs";

export default ({ marp }) => {
  return marp.use(GanttPlugin).use(CustomDiagramPlugin).use(hljs);
};
