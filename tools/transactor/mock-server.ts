import express, { Request, Response } from 'express';

const app = express();
const port = 3000;

app.use(express.json());

app.post('/task', (req: Request, res: Response) => {
  console.log('Received request:', JSON.stringify(req.body, null, 2));
  
  res.json({
    isCompliant: true,
    signers: ['0x0000000000000000000000000000000000000001'],
    signatures: ['0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'],
    expiryBlock: Math.floor(Date.now() / 1000) + 3600, // 1 hour from now
    taskId: `mock-task-id-${Math.floor(Math.random() * 10000)}`
  });
});

app.listen(port, () => {
  console.log(`Mock Predicate API server listening on port ${port}`);
});