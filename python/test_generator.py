from generic_controller import frame2uart, GenericController
from sklearn import datasets
from sklearn.preprocessing import normalize


gc = GenericController()

N = 32

X, Y = datasets.load_iris(return_X_y=True)
#X = X[::3]
#Y = Y[::3]

X = (normalize(X)*255).astype(int)
y_ohe = (
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1],
)

gc.set_batch_buffer_size(X.shape[0])
for i, (x, y) in enumerate(zip(X, Y)):
    gc.set_batch_entity(i, list(x), y_ohe[y])   
    
gc.queue_changes()  

gc.create_network(4, 8, 9, 8, 3, zero=True)
gc.queue_changes()  

gc.set_learning_mode(0)
#gc.set_modify_probability(round(1e-4 * 2**32))
gc.set_learning_actived(1)
gc.queue_changes()  

with open('commands.v', 'w') as f:
    f.write(frame2uart(gc.queue, delay=200))
