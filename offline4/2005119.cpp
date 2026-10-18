#include <iostream>
#include <thread>
#include <vector>
#include <semaphore.h>
#include <unistd.h>
#include <mutex>
#include <chrono>
#include <random>
#include <queue>
#include <condition_variable>
#include <algorithm> 

using namespace std;
using namespace chrono;

int N, M, w, x, y, z;  

// Semaphores and mutexes for synchronization
sem_t gallery1_capacity;
sem_t corridor_capacity;

mutex stair_mutex;
mutex print_mutex;
mutex step_mutex[3];
mutex gallery2_entry_mutex;

// Reader-Writer synchronization for photo booth
mutex resource_mutex;   // Protects access to photo booth
mutex read_try_mutex;   // Ensures no readers enter when a writer wants access
mutex read_count_mutex; // Protects read_count modification
mutex writer_mutex;     // Ensures only one writer accesses at a time

mutex premium_waiting_mutex;
int premium_waiting = 0;        // Counter to track waiting premium visitors
condition_variable cv_premium;  // To notify premium visitors
condition_variable cv_standard; // To notify standard visitors

int read_count = 0;   // Count of current readers (standard ticket holders)

struct Visitor {
    int id;
    bool is_premium;
};

auto start_time = steady_clock::now();

// Poisson distribution generator for inter-arrival times
int poisson_random(int lambda) {
    random_device rd;
    mt19937 gen(rd());
    poisson_distribution<int> poissonDist(lambda); 
    return poissonDist(gen); 
}

void print_timestamp(const string& message) {
    lock_guard<mutex> lock(print_mutex);  //prevent overlap
    auto now = steady_clock::now();
    auto timestamp = duration_cast<seconds>(now - start_time).count();
    cout << message << " at timestamp " << timestamp << "\n";
}

// Reader-Writer logic for managing photo booth access
void access_photo_booth(int visitor_id, bool premium) {
    print_timestamp("Visitor " + to_string(visitor_id) + " is about to enter the photo booth");
    this_thread::sleep_for(chrono::seconds(1)); 

    if (premium) {
        // Premium visitor (writer logic)
        {
            lock_guard<mutex> lock(premium_waiting_mutex);
            premium_waiting++;
        }

        // Writers get exclusive access
        unique_lock<mutex> writer_lock(resource_mutex);
        print_timestamp("Visitor " + to_string(visitor_id) + " is inside the photo booth");
        this_thread::sleep_for(chrono::seconds(z)); //  time in photo booth

        {
            lock_guard<mutex> lock(premium_waiting_mutex);
            premium_waiting--;
        }
        cv_standard.notify_all(); // Notify standard visitors waiting
    } 
    
    else {
        // Standard visitor (reader logic)
        {
            unique_lock<mutex> read_lock(read_try_mutex);
            cv_standard.wait(read_lock, [] {
                lock_guard<mutex> lock(premium_waiting_mutex);
                return premium_waiting == 0; // Wait until no premium visitors are waiting
            });

            {
                lock_guard<mutex> read_count_lock(read_count_mutex);
                read_count++;
                if (read_count == 1) {
                    resource_mutex.lock(); // First reader locks the resource
                }
            }
        }

        print_timestamp("Visitor " + to_string(visitor_id) + " is inside the photo booth");
        this_thread::sleep_for(chrono::seconds(z)); // time in photo booth

        {
            lock_guard<mutex> read_count_lock(read_count_mutex);
            read_count--;
            if (read_count == 0) {
                resource_mutex.unlock(); // Last reader unlocks the resource
            }
        }
    }
}


void visit_museum(int visitor_id, bool premium) {
    print_timestamp("Visitor " + to_string(visitor_id) + " has arrived at A");
    this_thread::sleep_for(chrono::seconds(w)); // Delay for hallway AB(w)
    print_timestamp("Visitor " + to_string(visitor_id) + " has arrived at B");
    this_thread::sleep_for(chrono::seconds(1));

    // Stairs (three steps to Gallery 1)
    for (int step = 1; step <= 3; ++step) {
        step_mutex[step - 1].lock();
        print_timestamp("Visitor " + to_string(visitor_id) + " is at step " + to_string(step));
        this_thread::sleep_for(chrono::seconds(1)); // Delay for steps
        step_mutex[step - 1].unlock();
    }

    // Enter Gallery 1
    sem_wait(&gallery1_capacity);
    print_timestamp("Visitor " + to_string(visitor_id) + " is at C (entered Gallery 1)");
    this_thread::sleep_for(chrono::seconds(x)); // Time in Gallery 1(x)
    print_timestamp("Visitor " + to_string(visitor_id) + " is at D (exiting Gallery 1)");
    sem_post(&gallery1_capacity);

    // Corridor DE (moving towards Gallery 2)
    sem_wait(&corridor_capacity);
    this_thread::sleep_for(chrono::seconds(2)); // arbitrary delay in corridor
    sem_post(&corridor_capacity);

    // Gallery 2 entry
    {
        lock_guard<mutex> lock(gallery2_entry_mutex);
        print_timestamp("Visitor " + to_string(visitor_id) + " is at E (entered Gallery 2)");
        this_thread::sleep_for(chrono::seconds(y)); // delay in Gallery 2(y)
    }

    access_photo_booth(visitor_id, premium);
}

int main(int argc, char* argv[]) {
    if (argc != 7) {
        cerr << "Usage: " << argv[0] << " <N> <M> <w> <x> <y> <z>\n";
        return 1; 
    }

    try {
        N = stoi(argv[1]); // Number of standard visitors
        M = stoi(argv[2]); // Number of premium visitors
        w = stoi(argv[3]); // Delay for hallway AB
        x = stoi(argv[4]); // Time spent in Gallery 1
        y = stoi(argv[5]); // Time spent in Gallery 2
        z = stoi(argv[6]); // Time in the photo booth
    } catch (const invalid_argument& e) {
        cerr << "Error: All arguments must be integers.\n";
        return 1;
    } catch (const out_of_range& e) {
        cerr << "Error: Argument value is out of range.\n";
        return 1;
    }

    // Initialize semaphores
    sem_init(&gallery1_capacity, 0, 5);
    sem_init(&corridor_capacity, 0, 3);


    vector<Visitor> all_visitors;
    for (int i = 0; i < N; ++i) {
        all_visitors.push_back({1001 + i, false});  // Standard visitors
    }
    for (int i = 0; i < M; ++i) {
        all_visitors.push_back({2001 + i, true});   // Premium visitors
    }

    // Shuffle the list of visitors to randomize their arrival order
    random_device rd;
    mt19937 g(rd());
    shuffle(all_visitors.begin(), all_visitors.end(), g);

    // Create threads for all visitors
    vector<thread> visitors;
    for (const auto& visitor : all_visitors) {
        visitors.emplace_back(visit_museum, visitor.id, visitor.is_premium);
        this_thread::sleep_for(chrono::seconds(poisson_random(1)));  // Poisson delay for each visitor
    }

    // Wait for all visitors to finish
    for (auto& t : visitors) {
        t.join();
    }

    sem_destroy(&gallery1_capacity);
    sem_destroy(&corridor_capacity);
    return 0;
}
