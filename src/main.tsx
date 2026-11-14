import React from "react";
import { createRoot } from "react-dom/client";
import { HashRouter } from "react-router-dom";
import App from "./App";
import { LabProvider } from "./lib/data";
import "./index.css";
createRoot(document.getElementById("root")!).render(<React.StrictMode><HashRouter><LabProvider><App /></LabProvider></HashRouter></React.StrictMode>);
