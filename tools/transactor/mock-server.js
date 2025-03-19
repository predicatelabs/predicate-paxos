"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var express_1 = require("express");
var app = (0, express_1.default)();
var port = 3000;
app.use(express_1.default.json());
app.post('/task', function (req, res) {
    console.log('Received request:', JSON.stringify(req.body, null, 2));
    res.json({
        isCompliant: true,
        signers: ['0x0000000000000000000000000000000000000001'],
        signatures: ['0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'],
        expiryBlock: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
        taskId: "mock-task-id-".concat(Math.floor(Math.random() * 10000))
    });
});
app.listen(port, function () {
    console.log("Mock Predicate API server listening on port ".concat(port));
});
