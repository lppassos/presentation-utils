import GanttPlugin from "/plugins/marp/gantt-diagram/index.js";
import hljs from "markdown-it-highlightjs";

export default ({ marp }) => {
  return marp.use(GanttPlugin).use(hljs);
};
