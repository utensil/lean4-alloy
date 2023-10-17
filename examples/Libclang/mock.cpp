int fun() {
    return 100;
}

int main() {
    int * p_int = new int;
    *p_int = fun();
    return 0;
}